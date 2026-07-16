# ── Variables ─────────────────────────────────────────────────────────────────

variable "key_pair_name" {
  description = "Name of the existing EC2 key pair for UAT SSH access"
  type        = string
  default     = "atoloan-uat"
}

variable "your_ip" {
  description = "Your public IP for SSH and kubectl access (e.g. 1.2.3.4/32)"
  type        = string
  default     = "0.0.0.0/0"   # ← replace with your IP for security e.g. "1.2.3.4/32"
}

variable "key_path" {
  description = "Local path to the UAT EC2 SSH private key (.pem file)"
  type        = string
  default     = "~/Downloads/atoloan-uat.pem"
}

# ── k3s shared cluster token ─────────────────────────────────────────────────
# Generated once, stored in Terraform state. Passed to both server and agent
# via user_data so they use a consistent token without manual coordination.

resource "random_password" "k3s_token_uat" {
  length  = 48
  special = false
}

# ── Security Group (shared by server and agent) ───────────────────────────────

resource "aws_security_group" "atoloan_k8s_uat" {
  name        = "atoloan-k8s-uat-sg"
  description = "Security group for atoloan k3s UAT cluster"
  vpc_id      = aws_vpc.atoloan_uat.id

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

  # kubectl from Mac
  ingress {
    description = "k3s API server (kubectl)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  # k3s inter-node: agent dials server API
  ingress {
    description = "k3s inter-node API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    self        = true
  }

  # Flannel VXLAN overlay (pod-to-pod traffic across nodes)
  ingress {
    description = "Flannel VXLAN"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
  }

  # kubelet health checks and exec/logs from server
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
    Name        = "atoloan-k8s-uat-sg"
    Environment = "uat"
    Project     = "atoloan"
  }
}

# ── k3s Server (control plane + ingress entry point) ─────────────────────────

resource "aws_instance" "atoloan_k8s_uat_server" {
  # Pinned (not data.aws_ami.ubuntu.id) — most_recent AMI lookups drift over
  # time as Canonical publishes patches, which forces a destroy+recreate of
  # this instance on the next unrelated apply. Update deliberately if needed.
  ami                    = "ami-0cf6185a5bb26f705" # matches currently running instance, pinned 2026-07-02
  instance_type          = "t3.small"
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.atoloan_uat_public_a.id
  vpc_security_group_ids = [aws_security_group.atoloan_k8s_uat.id]
  iam_instance_profile   = aws_iam_instance_profile.atoloan_ec2_uat.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # 2 GB swap — t3.small has 2 GB RAM
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    # Install k3s server
    # --tls-san: adds public IP to the TLS cert so kubectl works from Mac
    # --disable=traefik: we use nginx ingress instead
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    curl -sfL https://get.k3s.io | \
      K3S_TOKEN="${random_password.k3s_token_uat.result}" \
      INSTALL_K3S_EXEC="server --tls-san $PUBLIC_IP --disable=traefik" sh -

    chmod 644 /etc/rancher/k3s/k3s.yaml
    echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /home/ubuntu/.bashrc

    # Install Helm
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # Wait for k3s to be fully up before installing add-ons
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
    Name        = "atoloan-k8s-uat-server"
    Environment = "uat"
    Role        = "k3s-server"
    Project     = "atoloan"
  }
}

# ── k3s Agent (worker node) ───────────────────────────────────────────────────

resource "aws_instance" "atoloan_k8s_uat_agent" {
  # Pinned (not data.aws_ami.ubuntu.id) — see comment on atoloan_k8s_uat_server above.
  ami                    = "ami-0cf6185a5bb26f705" # matches currently running instance, pinned 2026-07-02
  instance_type          = "t3.small"
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.atoloan_uat_public_b.id
  vpc_security_group_ids = [aws_security_group.atoloan_k8s_uat.id]
  iam_instance_profile   = aws_iam_instance_profile.atoloan_ec2_uat.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  # Referencing server.private_ip here creates an implicit Terraform dependency:
  # the agent is not created until the server EC2 resource exists.
  user_data = <<-EOF
    #!/bin/bash
    set -e

    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    # Give the server time to finish installing k3s before the agent tries to join
    sleep 90

    curl -sfL https://get.k3s.io | \
      K3S_TOKEN="${random_password.k3s_token_uat.result}" \
      K3S_URL="https://${aws_instance.atoloan_k8s_uat_server.private_ip}:6443" sh -
  EOF

  tags = {
    Name        = "atoloan-k8s-uat-agent"
    Environment = "uat"
    Role        = "k3s-agent"
    Project     = "atoloan"
  }
}

# ── Elastic IP (server is the public entry point for all traffic) ─────────────

resource "aws_eip" "atoloan_k8s_uat" {
  instance = aws_instance.atoloan_k8s_uat_server.id
  domain   = "vpc"

  tags = {
    Name        = "atoloan-k8s-uat-eip"
    Environment = "uat"
    Project     = "atoloan"
  }
}

# ── Deploy k8s manifests after cluster + RDS are ready ───────────────────────

resource "null_resource" "deploy_k8s_manifests_uat" {
  depends_on = [
    aws_eip.atoloan_k8s_uat,
    aws_instance.atoloan_k8s_uat_agent,
    aws_db_instance.atoloan_postgres_uat,
    aws_secretsmanager_secret_version.atoloan_postgres_uat,
  ]

  triggers = {
    server_id = aws_instance.atoloan_k8s_uat_server.id
    agent_id  = aws_instance.atoloan_k8s_uat_agent.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for k3s server + helm add-ons + agent join to all finish
      sleep 300

      # Copy kubeconfig from server and point it at the Elastic IP
      mkdir -p ~/.kube
      scp -o StrictHostKeyChecking=no -i ${var.key_path} \
        ubuntu@${aws_eip.atoloan_k8s_uat.public_ip}:/etc/rancher/k3s/k3s.yaml \
        ~/.kube/config-aws-uat
      sed -i '' 's/127.0.0.1/${aws_eip.atoloan_k8s_uat.public_ip}/g' ~/.kube/config-aws-uat

      # Wait for both nodes to report Ready
      echo "Waiting for both nodes to be Ready..."
      KUBECONFIG=~/.kube/config-aws-uat kubectl wait nodes \
        --all --for=condition=Ready --timeout=300s

      # Wait for webhook deployments before applying CRD-backed resources
      KUBECONFIG=~/.kube/config-aws-uat kubectl rollout status deployment/external-secrets-webhook \
        -n external-secrets --timeout=120s
      KUBECONFIG=~/.kube/config-aws-uat kubectl rollout status deployment/cert-manager-webhook \
        -n cert-manager --timeout=120s

      # Patch nginx ingress with server's private IP so ingress gets an address
      # (LoadBalancer doesn't get an external IP on plain EC2)
      KUBECONFIG=~/.kube/config-aws-uat kubectl patch svc ingress-nginx-controller \
        -n ingress-nginx \
        -p '{"spec":{"externalIPs":["${aws_instance.atoloan_k8s_uat_server.private_ip}"]}}'

      # Deploy manifests in dependency order
      # Note: path is ../../k8s/ because this module lives in infrastructure/uat/
      KUBECONFIG=~/.kube/config-aws-uat kubectl apply -f ../../k8s/aws-uat/namespaces-aws-uat.yaml
      KUBECONFIG=~/.kube/config-aws-uat kubectl apply -f ../../k8s/aws-uat/namespace-quotas-uat.yaml
      KUBECONFIG=~/.kube/config-aws-uat kubectl apply -f ../../k8s/aws-uat/secret-store-aws-uat.yaml
      KUBECONFIG=~/.kube/config-aws-uat kubectl apply -f ../../k8s/aws-uat/backend-external-secret-aws-uat.yaml
      KUBECONFIG=~/.kube/config-aws-uat kubectl apply -f ../../k8s/aws-uat/frontend-aws-uat.yaml
      KUBECONFIG=~/.kube/config-aws-uat kubectl apply -f ../../k8s/aws-uat/backend-aws-uat.yaml
      KUBECONFIG=~/.kube/config-aws-uat kubectl apply -f ../../k8s/aws-uat/cert-manager-issuer-uat.yaml
      KUBECONFIG=~/.kube/config-aws-uat kubectl apply -f ../../k8s/aws-uat/frontend-ingress-uat.yaml
      KUBECONFIG=~/.kube/config-aws-uat kubectl apply -f ../../k8s/aws-uat/backend-ingress-uat.yaml

      # ── Health checks ─────────────────────────────────────────────────────────

      echo "Waiting for frontend to be ready..."
      KUBECONFIG=~/.kube/config-aws-uat kubectl rollout status deployment/atoloan-ui \
        -n atoloan-frontend-uat --timeout=120s

      echo "Waiting for backend ExternalSecret to sync..."
      KUBECONFIG=~/.kube/config-aws-uat kubectl wait externalsecret/rds-secrets \
        -n atoloan-backend-uat --for=condition=Ready --timeout=60s

      echo ""
      echo "UAT cluster ready. Node summary:"
      KUBECONFIG=~/.kube/config-aws-uat kubectl get nodes -o wide
      echo ""
      echo "Pod summary (non-running pods):"
      KUBECONFIG=~/.kube/config-aws-uat kubectl get pods -A \
        --field-selector=status.phase!=Running,status.phase!=Succeeded \
        | grep -v "^NAMESPACE" && echo "WARNING: some pods not Running" || echo "All pods healthy"
    EOT
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "uat_server_id" {
  value = aws_instance.atoloan_k8s_uat_server.id
}

output "uat_agent_id" {
  value = aws_instance.atoloan_k8s_uat_agent.id
}

output "uat_public_ip" {
  description = "Elastic IP — point uat.atoloan.com and api.uat.atoloan.com DNS here"
  value       = aws_eip.atoloan_k8s_uat.public_ip
}

output "uat_rds_endpoint" {
  description = "RDS endpoint (private — only reachable from within the UAT VPC)"
  value       = aws_db_instance.atoloan_postgres_uat.endpoint
}

output "uat_ssh_server" {
  description = "SSH into the k3s server"
  value       = "ssh -i ${var.key_path} ubuntu@${aws_eip.atoloan_k8s_uat.public_ip}"
}

output "uat_ssh_agent" {
  description = "SSH into the k3s agent (via server as jump host)"
  value       = "ssh -i ${var.key_path} -J ubuntu@${aws_eip.atoloan_k8s_uat.public_ip} ubuntu@${aws_instance.atoloan_k8s_uat_agent.private_ip}"
}

output "uat_kubeconfig_command" {
  description = "Fetch kubeconfig manually if needed"
  value       = "scp -i ${var.key_path} ubuntu@${aws_eip.atoloan_k8s_uat.public_ip}:/etc/rancher/k3s/k3s.yaml ~/.kube/config-aws-uat && sed -i '' 's/127.0.0.1/${aws_eip.atoloan_k8s_uat.public_ip}/g' ~/.kube/config-aws-uat"
}
