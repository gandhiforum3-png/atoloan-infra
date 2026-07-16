terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# ── Variables ────────────────────────────────────────────────────────────────

variable "key_pair_name" {
  description = "Name of the existing EC2 key pair to use for SSH access"
  type        = string
  default     = "atoloan-dev"
}

variable "your_ip" {
  description = "Your Mac's public IP for SSH access (find it at https://checkip.amazonaws.com)"
  type        = string
  default     = "0.0.0.0/0"   # ← replace with your IP for security e.g. "1.2.3.4/32"
}

variable "key_path" {
  description = "Local path to the EC2 SSH private key (.pem file)"
  type        = string
  default     = "~/Downloads/atoloan-dev.pem"
}

# ── Data: Latest Ubuntu 22.04 AMI ────────────────────────────────────────────

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# ── Security Group ────────────────────────────────────────────────────────────

resource "aws_security_group" "atoloan_k8s_dev" {
  name        = "atoloan-k8s-dev-sg"
  description = "Security group for atoloan k3s dev instance"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "k3s API (kubectl from Mac)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  ingress {
    description = "Postgres NodePort (DBeaver access)"
    from_port   = 30432
    to_port     = 30432
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── EC2 Instance ──────────────────────────────────────────────────────────────

resource "aws_instance" "atoloan_k8s_dev" {
  # Pinned (not data.aws_ami.ubuntu.id) — most_recent AMI lookups drift over
  # time as Canonical publishes patches, which forces a destroy+recreate of
  # this instance on the next unrelated apply. Update deliberately if needed.
  ami                    = "ami-0cf6185a5bb26f705" # Ubuntu 22.04 jammy amd64, pinned 2026-07-02
  instance_type          = "t3.small"
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.atoloan_k8s_dev.id]
  iam_instance_profile   = aws_iam_instance_profile.atoloan_ec2_dev.name

  root_block_device {
    volume_size = 10    # GB — enough for k3s + container images
    volume_type = "gp3"
  }

  # Bootstraps the instance: swap + k3s + helm on first boot
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Add 2GB swap (t2.small only has 2GB RAM)
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    # Install k3s with public IP in TLS cert so kubectl works from Mac
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--tls-san $PUBLIC_IP" sh -

    # Fix kubeconfig permissions for ubuntu user
    chmod 644 /etc/rancher/k3s/k3s.yaml
    echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /home/ubuntu/.bashrc

    # Install helm
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # Wait for k3s to be ready
    sleep 30

    # Install helm add-ons
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo add jetstack https://charts.jetstack.io
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo update

    helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace
    helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set installCRDs=true
    helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
  EOF

  tags = {
    Name        = "atoloan-k8s-dev"
    Environment = "dev"
    Project     = "atoloan"
  }
}

# ── Elastic IP (stable public IP that survives restarts) ──────────────────────

resource "aws_eip" "atoloan_k8s_dev" {
  instance = aws_instance.atoloan_k8s_dev.id
  domain   = "vpc"

  tags = {
    Name    = "atoloan-k8s-dev-eip"
    Project = "atoloan"
  }
}

# ── Deploy k8s manifests after EC2 is ready ──────────────────────────────────

resource "null_resource" "deploy_k8s_manifests" {
  depends_on = [aws_eip.atoloan_k8s_dev]

  triggers = {
    instance_id = aws_instance.atoloan_k8s_dev.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for k3s and helm add-ons to finish installing
      sleep 180

      # Copy kubeconfig
      mkdir -p ~/.kube
      scp -o StrictHostKeyChecking=no -i ${var.key_path} \
        ubuntu@${aws_eip.atoloan_k8s_dev.public_ip}:/etc/rancher/k3s/k3s.yaml \
        ~/.kube/config-aws-dev
      sed -i '' 's/127.0.0.1/${aws_eip.atoloan_k8s_dev.public_ip}/g' ~/.kube/config-aws-dev

      # Wait for webhooks to be ready before applying their CRDs
      KUBECONFIG=~/.kube/config-aws-dev kubectl rollout status deployment/external-secrets-webhook \
        -n external-secrets --timeout=120s
      KUBECONFIG=~/.kube/config-aws-dev kubectl rollout status deployment/cert-manager-webhook \
        -n cert-manager --timeout=120s

      # Patch nginx ingress with private IP so ingress gets an address
      KUBECONFIG=~/.kube/config-aws-dev kubectl patch svc ingress-nginx-controller \
        -n ingress-nginx \
        -p '{"spec":{"externalIPs":["${aws_instance.atoloan_k8s_dev.private_ip}"]}}'

      # Deploy manifests in order
      KUBECONFIG=~/.kube/config-aws-dev kubectl apply -f ../k8s/aws-dev/namespaces-aws-dev.yaml
      KUBECONFIG=~/.kube/config-aws-dev kubectl apply -f ../k8s/aws-dev/namespace-quotas.yaml
      KUBECONFIG=~/.kube/config-aws-dev kubectl apply -f ../k8s/aws-dev/secret-store-aws-dev.yaml
      KUBECONFIG=~/.kube/config-aws-dev kubectl apply -f ../k8s/aws-dev/postgres-external-secret-aws-dev.yaml
      KUBECONFIG=~/.kube/config-aws-dev kubectl apply -f ../k8s/aws-dev/postgres-storage-aws.yaml
      KUBECONFIG=~/.kube/config-aws-dev kubectl apply -f ../k8s/aws-dev/postgres-aws-dev.yaml
      KUBECONFIG=~/.kube/config-aws-dev kubectl apply -f ../k8s/aws-dev/postgres-nodeport-aws-dev.yaml
      KUBECONFIG=~/.kube/config-aws-dev kubectl apply -f ../k8s/aws-dev/frontend-aws-dev.yaml
      KUBECONFIG=~/.kube/config-aws-dev kubectl apply -f ../k8s/aws-dev/cert-manager-issuer.yaml
      KUBECONFIG=~/.kube/config-aws-dev kubectl apply -f ../k8s/aws-dev/frontend-ingress.yaml
      KUBECONFIG=~/.kube/config-aws-dev kubectl apply -f ../k8s/aws-dev/backend-ingress.yaml

      # ── Health checks — fail terraform if anything is not ready ──────────────

      echo "Waiting for postgres to be ready..."
      KUBECONFIG=~/.kube/config-aws-dev kubectl rollout status deployment/postgres \
        -n atoloan-postgres-dev --timeout=120s

      echo "Waiting for frontend to be ready..."
      KUBECONFIG=~/.kube/config-aws-dev kubectl rollout status deployment/atoloan-ui \
        -n atoloan-frontend-dev --timeout=120s

      echo "Checking ExternalSecret synced..."
      KUBECONFIG=~/.kube/config-aws-dev kubectl wait externalsecret/postgres-secrets \
        -n atoloan-postgres-dev \
        --for=condition=Ready --timeout=60s

      echo "Checking postgres-secret exists..."
      KUBECONFIG=~/.kube/config-aws-dev kubectl get secret postgres-secret \
        -n atoloan-postgres-dev

      echo ""
      echo "All systems go. Summary:"
      KUBECONFIG=~/.kube/config-aws-dev kubectl get pods -A \
        --field-selector=status.phase!=Running,status.phase!=Succeeded \
        | grep -v "^NAMESPACE" && echo "WARNING: some pods not Running" || echo "All pods healthy"
    EOT
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "instance_id" {
  value = aws_instance.atoloan_k8s_dev.id
}

output "public_ip" {
  description = "Elastic IP — use this for SSH and DNS records"
  value       = aws_eip.atoloan_k8s_dev.public_ip
}

output "ssh_command" {
  value = "ssh -i ${var.key_path} ubuntu@${aws_eip.atoloan_k8s_dev.public_ip}"
}

output "kubeconfig_command" {
  value = "scp -i ${var.key_path} ubuntu@${aws_eip.atoloan_k8s_dev.public_ip}:/etc/rancher/k3s/k3s.yaml ~/.kube/config-aws-dev && sed -i '' 's/127.0.0.1/${aws_eip.atoloan_k8s_dev.public_ip}/g' ~/.kube/config-aws-dev"
}
