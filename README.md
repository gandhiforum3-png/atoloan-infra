# atoloan-infra

Infrastructure-as-code for the **atoloan** platform. This repo contains all Terraform and Kubernetes manifests for every environment. No application code lives here.

---

## Table of Contents

- [Environments Overview](#environments-overview)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [AWS Account](#aws-account)
- [Local Development Setup](#local-development-setup)
- [Dev Environment (AWS EC2)](#dev-environment-aws-ec2)
- [UAT Environment (AWS EC2 + RDS)](#uat-environment-aws-ec2--rds)
- [Production Environment](#production-environment)
- [Secret Management](#secret-management)
- [DNS Setup (GoDaddy + Route 53)](#dns-setup-godaddy--route-53)
- [Kubectl Quick Reference](#kubectl-quick-reference)
- [Common Operations](#common-operations)
- [Troubleshooting](#troubleshooting)

---

## Environments Overview

| Environment | Compute | Database | Domain | Kubeconfig |
|---|---|---|---|---|
| **Local** | minikube (Mac) | postgres pod + Vault | `dev.atoloan.com` | default minikube |
| **Dev** | 1x t3.small EC2 (k3s) | postgres pod (PVC) | `aws-dev.atoloan.com` | `~/.kube/config-aws-dev` |
| **UAT** | 2x t3.small EC2 (k3s server + agent) | RDS db.t4g.micro PG16 | `uat.atoloan.com` | `~/.kube/config-aws-uat` |
| **Prod** | 2x t3.small EC2 (k3s server + agent) | RDS db.t4g.micro PG16 | `atoloans.com` | `~/.kube/config-aws-prod` |

---

## Repository Structure

```
infrastructure/
  ec2-dev.tf            # Dev: single EC2 + Elastic IP + k3s bootstrap
  iam-ec2-dev.tf        # Dev: IAM role for Secrets Manager access
  dns/                  # Shared: Route 53 hosted zone for atoloans.com (never destroy)
    provider.tf
    dns.tf
  uat/                  # UAT: isolated Terraform module (separate state)
    provider.tf
    vpc-uat.tf          # VPC 10.1.0.0/16
    ec2-uat.tf          # k3s server + agent + EIP + manifest deploy
    rds-uat.tf          # RDS db.t4g.micro PostgreSQL 16
    iam-ec2-uat.tf
    secrets-uat.tf      # Secrets Manager: atoloan/postgres-uat
  prod/                 # Prod: isolated Terraform module (separate state)
    provider.tf
    vpc-prod.tf         # VPC 10.2.0.0/16
    ec2-prod.tf         # k3s server + agent + EIP + manifest deploy
    rds-prod.tf         # RDS db.t4g.micro PostgreSQL 16, deletion_protection=true
    iam-ec2-prod.tf
    secrets-prod.tf     # Secrets Manager: atoloan/postgres-prod
    dns-records-prod.tf # Route 53 A records + RDS CNAME alias

k8s/
  backend/              # Local: postgres Deployment, PVC, backend Ingress
  frontend/             # Local: frontend Deployment, Ingress
  secrets/
    local/              # Local: Vault ClusterSecretStore
    aws/                # AWS: Secrets Manager ClusterSecretStore
    postgres-external-secret.yaml
  aws-dev/              # Dev (EC2): all manifests for dev cluster
  aws-uat/              # UAT: all manifests for UAT cluster
  aws-prod/             # Prod: all manifests for prod cluster
  namespaces.yaml       # Local namespaces
  coredns-patch.yaml    # Local CoreDNS custom hosts (minikube only)
  vault-ingress.yaml    # Local Vault bridge (minikube only)
```

---

## Prerequisites

Install all of the following before working in this repo.

### Required tools

| Tool | Version | Install |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.5 | `brew install terraform` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/) | >= 1.28 | `brew install kubectl` |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-mac.html) | >= 2.0 | `brew install awscli` |
| [Helm](https://helm.sh/docs/intro/install/) | >= 3.0 | `brew install helm` |
| [minikube](https://minikube.sigs.k8s.io/docs/start/) | >= 1.32 | `brew install minikube` (local only) |
| [Vault CLI](https://developer.hashicorp.com/vault/install) | >= 1.15 | `brew install vault` (local only) |

### AWS credentials

You need access to AWS account `017601971228`. Request an IAM user from the team lead.

Once you have credentials:
```bash
aws configure
# AWS Access Key ID: <your key>
# AWS Secret Access Key: <your secret>
# Default region: us-east-2
# Default output format: json
```

Verify:
```bash
aws sts get-caller-identity
```

### EC2 SSH keys

Request the following `.pem` files from the team lead and place them in `~/Downloads/`:

| Key file | Used for |
|---|---|
| `atoloan-dev.pem` | SSH into dev EC2 |
| `atoloan-uat.pem` | SSH into UAT EC2 nodes |
| `atoloan-prod.pem` | SSH into prod EC2 nodes |

```bash
chmod 400 ~/Downloads/atoloan-dev.pem
chmod 400 ~/Downloads/atoloan-uat.pem
chmod 400 ~/Downloads/atoloan-prod.pem
```

---

## AWS Account

| | |
|---|---|
| **Account ID** | `017601971228` |
| **Region** | `us-east-2` (Ohio) |
| **IAM User pattern** | `atoloan-*` |

All AWS resources follow the prefix `atoloan-`.

---

## Local Development Setup

Uses minikube + Vault on your Mac.

### 1. Start minikube

```bash
minikube start
minikube addons enable ingress
minikube tunnel   # keep running in a separate terminal
```

### 2. Start Vault

```bash
vault server -dev -dev-root-token-id="root"
export VAULT_ADDR='http://127.0.0.1:8200'

# Store postgres credentials
vault kv put secret/atoloan/postgres \
  PGUSER=atoloanuser \
  PGPASSWORD=<password> \
  PGDATABASE=atoloandb
```

### 3. Deploy manifests

```bash
kubectl apply -f k8s/namespaces.yaml
kubectl apply -f k8s/secrets/local/secret-setup-vault.yaml
kubectl apply -f k8s/secrets/postgres-external-secret.yaml
kubectl apply -f k8s/backend/postgres-storage.yaml
kubectl apply -f k8s/backend/postgres.yaml
kubectl apply -f k8s/frontend/frontend.yaml
kubectl apply -f k8s/coredns-patch.yaml
kubectl rollout restart deployment coredns -n kube-system
```

### 4. Add to `/etc/hosts`

```
127.0.0.1  dev.atoloan.com
127.0.0.1  dev.atoloan.api.com
127.0.0.1  dev.vault.atoloan.com
127.0.0.1  dev.kube.atoloan.com
```

### CoreDNS note

`k8s/coredns-patch.yaml` has hardcoded IPs that change on every minikube restart. After restart:
```bash
# Get new nginx ClusterIP
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}'

# Get new host.minikube.internal IP
minikube ssh "cat /etc/hosts" | grep host.minikube.internal
```
Update both values in `coredns-patch.yaml` then re-apply.

---

## Dev Environment (AWS EC2)

Single t3.small EC2 running k3s. Postgres runs as a pod (not RDS).

### Deploy

```bash
cd infrastructure/
terraform init
terraform apply
```

Terraform auto-deploys all `k8s/aws-dev/` manifests after EC2 boots.

### Access

```bash
export KUBECONFIG=~/.kube/config-aws-dev
kubectl get nodes
```

SSH:
```bash
ssh -i ~/Downloads/atoloan-dev.pem ubuntu@3.135.161.145
```

Add to `/etc/hosts`:
```
3.135.161.145  aws-dev.atoloan.com
3.135.161.145  api.aws-dev.atoloan.com
```

---

## UAT Environment (AWS EC2 + RDS)

Two t3.small EC2 instances (k3s server + agent) with managed RDS PostgreSQL 16. Data persists independently of EC2 state.

### First-time setup

**1. Create EC2 key pair:**
```bash
aws ec2 create-key-pair --key-name atoloan-uat --region us-east-2 \
  --query 'KeyMaterial' --output text > ~/Downloads/atoloan-uat.pem
chmod 400 ~/Downloads/atoloan-uat.pem
```

**2. Deploy:**
```bash
cd infrastructure/uat/
terraform init
terraform apply
```

Terraform creates: VPC → IAM → Security Groups → RDS → EC2 → EIP → Secrets Manager → deploys k8s manifests. Takes ~15-20 min (RDS creation takes ~10 min).

### Access

```bash
export KUBECONFIG=~/.kube/config-aws-uat
kubectl get nodes   # should show 2 nodes: server + agent
```

SSH into server:
```bash
ssh -i ~/Downloads/atoloan-uat.pem ubuntu@<uat_public_ip>
```

SSH into agent (via server as jump host):
```bash
ssh -i ~/Downloads/atoloan-uat.pem -J ubuntu@<uat_public_ip> ubuntu@<agent_private_ip>
```

Add to `/etc/hosts` for local testing:
```
<uat_public_ip>  uat.atoloan.com api.uat.atoloan.com
```

### UAT URLs

| Service | URL |
|---|---|
| Frontend | `https://uat.atoloan.com` |
| Backend API | `https://api.uat.atoloan.com` |

---

## Production Environment

Two t3.small EC2 instances (k3s server + agent) with managed RDS PostgreSQL 16. DNS managed by Route 53. RDS has deletion protection enabled.

### First-time setup (run once)

**Step 1 — Deploy the Route 53 DNS zone:**
```bash
cd infrastructure/dns/
terraform init
terraform apply
```

Copy the 4 nameservers from the output.

**Step 2 — Update GoDaddy nameservers:**

GoDaddy → My Products → DNS → `atoloans.com` → Nameservers → Custom → paste the 4 AWS nameservers.

Wait up to 48 hours for DNS propagation before proceeding.

**Step 3 — Create EC2 key pair:**
```bash
aws ec2 create-key-pair --key-name atoloan-prod --region us-east-2 \
  --query 'KeyMaterial' --output text > ~/Downloads/atoloan-prod.pem
chmod 400 ~/Downloads/atoloan-prod.pem
```

**Step 4 — Deploy prod infrastructure:**
```bash
cd infrastructure/prod/
terraform init
terraform apply
```

### Access

```bash
export KUBECONFIG=~/.kube/config-aws-prod
kubectl get nodes   # should show 2 nodes: server + agent
```

SSH into server:
```bash
ssh -i ~/Downloads/atoloan-prod.pem ubuntu@<prod_public_ip>
```

SSH into agent:
```bash
ssh -i ~/Downloads/atoloan-prod.pem -J ubuntu@<prod_public_ip> ubuntu@<agent_private_ip>
```

### Prod URLs

| Service | URL |
|---|---|
| Frontend | `https://atoloans.com` |
| Frontend (www) | `https://www.atoloans.com` |
| Backend API | `https://api.atoloans.com` |
| RDS alias | `postgres.atoloans.com` (internal use only) |

---

## Secret Management

### Local (Vault)

Vault runs on your Mac at `http://127.0.0.1:8200`.

```bash
vault kv put secret/atoloan/postgres \
  PGUSER=atoloanuser \
  PGPASSWORD=<password> \
  PGDATABASE=atoloandb
```

### Dev (AWS Secrets Manager)

```bash
aws secretsmanager create-secret --name atoloan/postgres --region us-east-2 \
  --secret-string '{"PGUSER":"atoloanuser","PGPASSWORD":"<pass>","PGDATABASE":"atoloandb"}'
```

### UAT (AWS Secrets Manager)

Secret `atoloan/postgres-uat` is created and populated **automatically by Terraform** when UAT is deployed. No manual steps needed.

### Prod (AWS Secrets Manager)

The following secrets must exist in `us-east-2` before deploying prod manifests:

| Secret path | Keys | Who creates it |
|---|---|---|
| `atoloan/postgres-prod` | `PGUSER`, `PGPASSWORD`, `PGDATABASE`, `PGHOST`, `PGPORT` | Terraform (automatic) |
| `atoloan/openai` | `OPENAI_API_KEY` | Manual — request from team lead |
| `atoloan/sevencredit` | `SEVENCREDIT_ACCOUNT`, `SEVENCREDIT_PASSWORD`, `SEVENCREDIT_CLIENT_ID`, `SEVENCREDIT_CLIENT_SECRET` | Manual — request from team lead |

Create manual secrets:
```bash
aws secretsmanager create-secret --name atoloan/openai --region us-east-2 \
  --secret-string '{"OPENAI_API_KEY":"<key>"}'

aws secretsmanager create-secret --name atoloan/sevencredit --region us-east-2 \
  --secret-string '{"SEVENCREDIT_ACCOUNT":"<val>","SEVENCREDIT_PASSWORD":"<val>","SEVENCREDIT_CLIENT_ID":"<val>","SEVENCREDIT_CLIENT_SECRET":"<val>"}'
```

Force ExternalSecret re-sync:
```bash
# UAT
kubectl annotate externalsecret postgres-secrets -n atoloan-postgres-uat \
  force-sync=$(date +%s) --overwrite

# Prod
kubectl annotate externalsecret rds-secrets -n atoloan-backend-prod \
  force-sync=$(date +%s) --overwrite
```

---

## DNS Setup (GoDaddy + Route 53)

DNS for `atoloans.com` is managed by Route 53. GoDaddy is configured to delegate to AWS nameservers.

**Architecture:**
- `infrastructure/dns/` owns the Route 53 hosted zone — **never run `terraform destroy` in this directory**
- `infrastructure/prod/dns-records-prod.tf` creates the A records and CNAME aliases
- If prod is torn down and rebuilt, DNS records are recreated automatically; the zone survives

**RDS CNAME alias:** `postgres.atoloans.com` → RDS endpoint. If RDS is ever recreated, only this CNAME needs updating — all application config stays the same.

---

## Kubectl Quick Reference

```bash
# Switch environments
export KUBECONFIG=~/.kube/config-aws-dev    # dev
export KUBECONFIG=~/.kube/config-aws-uat    # UAT
export KUBECONFIG=~/.kube/config-aws-prod   # prod

# Check nodes
kubectl get nodes -o wide

# Check all pods
kubectl get pods -A

# Check pods in a namespace
kubectl get pods -n atoloan-backend-prod
kubectl get pods -n atoloan-frontend-prod

# Check ingress
kubectl get ingress -A

# Check ExternalSecrets
kubectl get externalsecret -A

# View pod logs
kubectl logs -f deployment/atoloan-api -n atoloan-backend-prod
kubectl logs -f deployment/atoloan-ui -n atoloan-frontend-prod

# Exec into a pod
kubectl exec -it <pod-name> -n atoloan-backend-prod -- bash
```

---

## Common Operations

### Deploy a new image (rolling restart, zero downtime)

```bash
# Frontend
kubectl rollout restart deployment/atoloan-ui -n atoloan-frontend-prod

# Backend
kubectl rollout restart deployment/atoloan-api -n atoloan-backend-prod

# Watch progress
kubectl rollout status deployment/atoloan-api -n atoloan-backend-prod
```

### Roll back a deployment

```bash
kubectl rollout undo deployment/atoloan-api -n atoloan-backend-prod
```

### Check running AWS instances

```bash
aws ec2 describe-instances --region us-east-2 \
  --filters "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].[Tags[?Key=='Name'].Value|[0],InstanceType,PublicIpAddress,State.Name]" \
  --output table
```

### Fetch kubeconfig manually (if lost)

```bash
# UAT
scp -i ~/Downloads/atoloan-uat.pem ubuntu@<uat_ip>:/etc/rancher/k3s/k3s.yaml ~/.kube/config-aws-uat
sed -i '' 's/127.0.0.1/<uat_ip>/g' ~/.kube/config-aws-uat

# Prod
scp -i ~/Downloads/atoloan-prod.pem ubuntu@<prod_ip>:/etc/rancher/k3s/k3s.yaml ~/.kube/config-aws-prod
sed -i '' 's/127.0.0.1/<prod_ip>/g' ~/.kube/config-aws-prod
```

### Verify frontend is calling the correct backend URL

```bash
kubectl exec -it <frontend-pod> -n atoloan-frontend-prod -- \
  sh -c 'grep -o "https\?://[a-zA-Z0-9./_-]*" /usr/share/nginx/html/assets/*.js | sort -u'
```

Should include `https://api.atoloans.com`. If it shows `http://localhost`, rebuild the frontend image with `VITE_API_URL=https://api.atoloans.com`.

### Postgres backup (local)

```bash
kubectl exec -n atoloan-postgres \
  $(kubectl get pod -n atoloan-postgres -l app=postgres -o jsonpath='{.items[0].metadata.name}') \
  -- pg_dumpall -U atoloanuser > postgres-backup.sql
```

### Port-forward postgres for DBeaver (local)

```bash
kubectl port-forward svc/postgres-svc 5433:5432 -n atoloan-postgres
```

---

## Troubleshooting

### Ingress has no ADDRESS

```bash
# Patch nginx ingress with server's private IP
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  -p '{"spec":{"externalIPs":["<server_private_ip>"]}}'

# Get server private IP
kubectl get nodes -o wide
```

### ExternalSecret not syncing

```bash
# Check status
kubectl describe externalsecret rds-secrets -n atoloan-backend-prod

# Force re-sync
kubectl annotate externalsecret rds-secrets -n atoloan-backend-prod \
  force-sync=$(date +%s) --overwrite
```

### Pod stuck in Pending

```bash
kubectl describe pod <pod-name> -n atoloan-backend-prod
# Look for: Insufficient memory/cpu → reduce requests in the manifest
# Look for: 0/2 nodes available → check node taints or resource quotas
```

### Backend returns wrong route (404 on API paths)

Ensure the backend ingress does **not** have `nginx.ingress.kubernetes.io/rewrite-target: /`. That annotation strips the request path and breaks all API routes.

### CoreDNS stale IPs (local only)

After minikube restart, update IPs in `k8s/coredns-patch.yaml`:
```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}'
minikube ssh "cat /etc/hosts" | grep host.minikube.internal
```
Then re-apply and restart CoreDNS:
```bash
kubectl apply -f k8s/coredns-patch.yaml
kubectl rollout restart deployment coredns -n kube-system
```
