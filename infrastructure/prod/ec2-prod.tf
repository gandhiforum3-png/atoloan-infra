# ── Variables ─────────────────────────────────────────────────────────────────

variable "key_pair_name" {
  description = "Name of the existing EC2 key pair for prod SSH access"
  type        = string
  default     = "atoloan-prod"
}

variable "your_ip" {
  description = "Your public IP for SSH and kubectl access (e.g. 1.2.3.4/32)"
  type        = string
  default     = "0.0.0.0/0"   # ← replace with your IP for security e.g. "1.2.3.4/32"
}

variable "key_path" {
  description = "Local path to the prod EC2 SSH private key (.pem file)"
  type        = string
  default     = "~/Downloads/atoloan-prod.pem"
}

# ── k3s shared cluster token ─────────────────────────────────────────────────

resource "random_password" "k3s_token_prod" {
  length  = 48
  special = false
}

# ── Security Group (shared by server and agent) ───────────────────────────────

resource "aws_security_group" "atoloan_k8s_prod" {
  name        = "atoloan-k8s-prod-sg"
  description = "Security group for atoloan k3s prod cluster"
  vpc_id      = aws_vpc.atoloan_prod.id

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
    description = "k3s API server (kubectl)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  ingress {
    description = "k3s inter-node API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Flannel VXLAN"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
  }

  ingress {
    description = "kubelet"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "atoloan-k8s-prod-sg"
    Environment = "prod"
    Project     = "atoloan"
  }
}

# ── k3s Server (control plane + ingress entry point) ─────────────────────────

resource "aws_instance" "atoloan_k8s_prod_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.atoloan_prod_public_a.id
  vpc_security_group_ids = [aws_security_group.atoloan_k8s_prod.id]
  iam_instance_profile   = aws_iam_instance_profile.atoloan_ec2_prod.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    curl -sfL https://get.k3s.io | \
      K3S_TOKEN="${random_password.k3s_token_prod.result}" \
      INSTALL_K3S_EXEC="server --tls-san $PUBLIC_IP --disable=traefik" sh -

    chmod 644 /etc/rancher/k3s/k3s.yaml
    echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /home/ubuntu/.bashrc

    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    sleep 30

    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo add jetstack    https://charts.jetstack.io
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo update

    helm install ingress-nginx ingress-nginx/ingress-nginx \
      -n ingress-nginx --create-namespace
    helm install cert-manager jetstack/cert-manager \
      -n cert-manager --create-namespace --set installCRDs=true
    helm install external-secrets external-secrets/external-secrets \
      -n external-secrets --create-namespace
  EOF

  tags = {
    Name        = "atoloan-k8s-prod-server"
    Environment = "prod"
    Role        = "k3s-server"
    Project     = "atoloan"
  }
}

# ── k3s Agent (worker node) ───────────────────────────────────────────────────

resource "aws_instance" "atoloan_k8s_prod_agent" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.atoloan_prod_public_b.id
  vpc_security_group_ids = [aws_security_group.atoloan_k8s_prod.id]
  iam_instance_profile   = aws_iam_instance_profile.atoloan_ec2_prod.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    sleep 90

    curl -sfL https://get.k3s.io | \
      K3S_TOKEN="${random_password.k3s_token_prod.result}" \
      K3S_URL="https://${aws_instance.atoloan_k8s_prod_server.private_ip}:6443" sh -
  EOF

  tags = {
    Name        = "atoloan-k8s-prod-agent"
    Environment = "prod"
    Role        = "k3s-agent"
    Project     = "atoloan"
  }
}

# ── Elastic IP ────────────────────────────────────────────────────────────────

resource "aws_eip" "atoloan_k8s_prod" {
  instance = aws_instance.atoloan_k8s_prod_server.id
  domain   = "vpc"

  tags = {
    Name        = "atoloan-k8s-prod-eip"
    Environment = "prod"
    Project     = "atoloan"
  }
}

# ── Deploy k8s manifests after cluster + RDS + DNS are ready ─────────────────

resource "null_resource" "deploy_k8s_manifests_prod" {
  depends_on = [
    aws_eip.atoloan_k8s_prod,
    aws_instance.atoloan_k8s_prod_agent,
    aws_db_instance.atoloan_postgres_prod,
    aws_secretsmanager_secret_version.atoloan_postgres_prod,
    aws_route53_record.atoloans_root,
    aws_route53_record.atoloans_api,
    aws_route53_record.atoloans_postgres,
  ]

  triggers = {
    server_id = aws_instance.atoloan_k8s_prod_server.id
    agent_id  = aws_instance.atoloan_k8s_prod_agent.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      sleep 300

      mkdir -p ~/.kube
      scp -o StrictHostKeyChecking=no -i ${var.key_path} \
        ubuntu@${aws_eip.atoloan_k8s_prod.public_ip}:/etc/rancher/k3s/k3s.yaml \
        ~/.kube/config-aws-prod
      sed -i '' 's/127.0.0.1/${aws_eip.atoloan_k8s_prod.public_ip}/g' ~/.kube/config-aws-prod

      echo "Waiting for both nodes to be Ready..."
      KUBECONFIG=~/.kube/config-aws-prod kubectl wait nodes \
        --all --for=condition=Ready --timeout=300s

      KUBECONFIG=~/.kube/config-aws-prod kubectl rollout status deployment/external-secrets-webhook \
        -n external-secrets --timeout=120s
      KUBECONFIG=~/.kube/config-aws-prod kubectl rollout status deployment/cert-manager-webhook \
        -n cert-manager --timeout=120s

      KUBECONFIG=~/.kube/config-aws-prod kubectl patch svc ingress-nginx-controller \
        -n ingress-nginx \
        -p '{"spec":{"externalIPs":["${aws_instance.atoloan_k8s_prod_server.private_ip}"]}}'

      KUBECONFIG=~/.kube/config-aws-prod kubectl apply -f ../../k8s/aws-prod/namespaces-aws-prod.yaml
      KUBECONFIG=~/.kube/config-aws-prod kubectl apply -f ../../k8s/aws-prod/namespace-quotas-prod.yaml
      KUBECONFIG=~/.kube/config-aws-prod kubectl apply -f ../../k8s/aws-prod/secret-store-aws-prod.yaml
      KUBECONFIG=~/.kube/config-aws-prod kubectl apply -f ../../k8s/aws-prod/backend-external-secret-aws-prod.yaml
      KUBECONFIG=~/.kube/config-aws-prod kubectl apply -f ../../k8s/aws-prod/frontend-aws-prod.yaml
      KUBECONFIG=~/.kube/config-aws-prod kubectl apply -f ../../k8s/aws-prod/backend-aws-prod.yaml
      KUBECONFIG=~/.kube/config-aws-prod kubectl apply -f ../../k8s/aws-prod/cert-manager-issuer-prod.yaml
      KUBECONFIG=~/.kube/config-aws-prod kubectl apply -f ../../k8s/aws-prod/frontend-ingress-prod.yaml
      # backend ingress is defined inside backend-aws-prod.yaml — no separate file

      echo "Waiting for frontend to be ready..."
      KUBECONFIG=~/.kube/config-aws-prod kubectl rollout status deployment/atoloan-ui \
        -n atoloan-frontend-prod --timeout=120s

      echo "Waiting for backend ExternalSecret to sync..."
      KUBECONFIG=~/.kube/config-aws-prod kubectl wait externalsecret/rds-secrets \
        -n atoloan-backend-prod --for=condition=Ready --timeout=60s

      echo ""
      echo "Prod cluster ready. Node summary:"
      KUBECONFIG=~/.kube/config-aws-prod kubectl get nodes -o wide
      echo ""
      KUBECONFIG=~/.kube/config-aws-prod kubectl get pods -A \
        --field-selector=status.phase!=Running,status.phase!=Succeeded \
        | grep -v "^NAMESPACE" && echo "WARNING: some pods not Running" || echo "All pods healthy"
    EOT
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "prod_server_id" {
  value = aws_instance.atoloan_k8s_prod_server.id
}

output "prod_agent_id" {
  value = aws_instance.atoloan_k8s_prod_agent.id
}

output "prod_public_ip" {
  description = "Elastic IP — already pointed at atoloans.com via Route 53"
  value       = aws_eip.atoloan_k8s_prod.public_ip
}

output "prod_rds_endpoint" {
  description = "Raw RDS endpoint (use postgres.atoloans.com alias in app config)"
  value       = aws_db_instance.atoloan_postgres_prod.endpoint
}

output "prod_ssh_server" {
  value = "ssh -i ${var.key_path} ubuntu@${aws_eip.atoloan_k8s_prod.public_ip}"
}

output "prod_ssh_agent" {
  value = "ssh -i ${var.key_path} -J ubuntu@${aws_eip.atoloan_k8s_prod.public_ip} ubuntu@${aws_instance.atoloan_k8s_prod_agent.private_ip}"
}

output "prod_kubeconfig_command" {
  value = "scp -i ${var.key_path} ubuntu@${aws_eip.atoloan_k8s_prod.public_ip}:/etc/rancher/k3s/k3s.yaml ~/.kube/config-aws-prod && sed -i '' 's/127.0.0.1/${aws_eip.atoloan_k8s_prod.public_ip}/g' ~/.kube/config-aws-prod"
}
