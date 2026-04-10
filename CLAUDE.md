# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Infrastructure-as-code for the **atoloan** platform. Two active environments:
- **Local** — minikube on Mac, Vault for secrets
- **AWS Dev** — k3s on EC2 (`t3.small`, `us-east-2`), AWS Secrets Manager for secrets

No application code lives here — only infrastructure definitions.

## Established conventions — never deviate without asking

| Convention | Value |
|---|---|
| AWS Dev EC2 | `t3.small`, `us-east-2`, Elastic IP `3.135.161.145` |
| AWS Dev namespaces | `atoloan-postgres-dev`, `atoloan-backend-dev`, `atoloan-frontend-dev` |
| Local namespaces | `atoloan-postgres`, `atoloan-backend`, `atoloan-frontend`, `atoloan-vault` |
| ECR pattern | `atoloan-<service>` |
| AWS resource prefix | `atoloan-` |
| IAM role pattern | `atoloan-<service>-pod-role` |
| DB | database `atoloandb` / user `atoloanuser` |
| AWS region | `us-east-2` (EC2 dev) |
| Secret path | `atoloan/postgres` in AWS Secrets Manager |

## Repo layout

```
infrastructure/
  ec2-dev.tf          ← EC2 + Elastic IP + Security Group + null_resource deploy
  iam-ec2-dev.tf      ← IAM role + instance profile for EC2 Secrets Manager access
k8s/
  namespaces.yaml     ← local namespaces with ResourceQuota + LimitRange
  coredns-patch.yaml  ← CoreDNS custom hosts (minikube only — hardcoded IPs)
  backend/            ← postgres Deployment, Service, PVC, backend Ingress (local)
  frontend/           ← React UI Deployment, Service, Ingress (local)
  secrets/
    aws/              ← ClusterSecretStore for AWS Secrets Manager (EKS/production)
    local/            ← ClusterSecretStore for Vault (local dev)
    postgres-external-secret.yaml  ← local ExternalSecret
  aws-dev/            ← ALL AWS dev specific manifests (use these on EC2)
  vault-ingress.yaml  ← Vault bridge (minikube only)
  dashboard-ingress.yaml  ← k8s dashboard (minikube only)
```

## Two environments — which files to use

| File location | Use on | Do NOT use on |
|---|---|---|
| `k8s/backend/`, `k8s/frontend/` | Local minikube | AWS EC2 |
| `k8s/secrets/local/` | Local minikube | AWS EC2 |
| `k8s/coredns-patch.yaml` | Local minikube | AWS EC2 |
| `k8s/vault-ingress.yaml` | Local minikube | AWS EC2 |
| `k8s/aws-dev/` | AWS EC2 | Local minikube |

## AWS Dev — deploy everything via Terraform

```bash
cd infrastructure/
terraform init
terraform apply   # creates EC2, Elastic IP, deploys all k8s manifests automatically
```

Terraform auto-runs `null_resource.deploy_k8s_manifests` which:
1. Waits 2 min for k3s + helm to finish
2. Copies kubeconfig to `~/.kube/config-aws-dev`
3. Patches nginx ingress with private IP
4. Applies all `k8s/aws-dev/` manifests in order

To use kubectl against AWS dev from Mac:
```bash
export KUBECONFIG=~/.kube/config-aws-dev
kubectl get nodes
```

## AWS Dev — manual kubectl deploy order (if needed)

```bash
export KUBECONFIG=~/.kube/config-aws-dev
kubectl apply -f k8s/aws-dev/namespaces-aws-dev.yaml
kubectl apply -f k8s/aws-dev/namespace-quotas.yaml
kubectl apply -f k8s/aws-dev/secret-store-aws-dev.yaml
kubectl apply -f k8s/aws-dev/postgres-external-secret-aws-dev.yaml
kubectl apply -f k8s/aws-dev/postgres-storage-aws.yaml
kubectl apply -f k8s/aws-dev/postgres-aws-dev.yaml
kubectl apply -f k8s/aws-dev/frontend-aws-dev.yaml
kubectl apply -f k8s/aws-dev/cert-manager-issuer.yaml
kubectl apply -f k8s/aws-dev/frontend-ingress.yaml
kubectl apply -f k8s/aws-dev/backend-ingress.yaml
```

## AWS Dev — nginx ingress fix (required on k3s EC2)

LoadBalancer services don't get external IPs on plain EC2. After deploy:
```bash
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  -p '{"spec":{"externalIPs":["172.31.46.234"]}}'  # private IP of EC2
```

## Local development (minikube)

```bash
minikube start
minikube tunnel          # keep running in separate terminal

# First time only
minikube addons enable ingress

kubectl apply -f k8s/namespaces.yaml
kubectl apply -f k8s/secrets/local/secret-setup-vault.yaml
kubectl apply -f k8s/secrets/postgres-external-secret.yaml
kubectl apply -f k8s/backend/postgres-storage.yaml
kubectl apply -f k8s/backend/postgres.yaml
kubectl apply -f k8s/frontend/frontend.yaml
kubectl apply -f k8s/coredns-patch.yaml && kubectl rollout restart deployment coredns -n kube-system
```

Local `/etc/hosts` entries required:
```
127.0.0.1  dev.atoloan.com
127.0.0.1  dev.atoloan.api.com
127.0.0.1  dev.vault.atoloan.com
127.0.0.1  dev.kube.atoloan.com
```

AWS dev `/etc/hosts` entry required:
```
3.135.161.145  aws-dev.atoloan.com
3.135.161.145  api.aws-dev.atoloan.com
```

## Secret management

**Local:** Vault on host Mac at `http://127.0.0.1:8200`. Token stored in `vault-token` secret in `atoloan-vault` namespace.
```bash
vault server -dev -dev-root-token-id="root"
export VAULT_ADDR='http://127.0.0.1:8200'
vault kv put secret/atoloan/postgres PGUSER=atoloanuser PGPASSWORD=<pass> PGDATABASE=atoloandb
```

**AWS Dev:** AWS Secrets Manager, region `us-east-2`. EC2 IAM instance profile provides access (no IRSA).
```bash
aws secretsmanager create-secret --name atoloan/postgres --region us-east-2 \
  --secret-string '{"PGUSER":"atoloanuser","PGPASSWORD":"<pass>","PGDATABASE":"atoloandb"}'
```

## Common operations

```bash
# Force ExternalSecret re-sync (local)
kubectl annotate externalsecret postgres-secrets -n atoloan-postgres force-sync=$(date +%s) --overwrite

# Force ExternalSecret re-sync (aws-dev)
kubectl annotate externalsecret postgres-secrets -n atoloan-postgres-dev force-sync=$(date +%s) --overwrite

# Postgres backup (local)
kubectl exec -n atoloan-postgres $(kubectl get pod -n atoloan-postgres -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- pg_dumpall -U atoloanuser > postgres-backup.sql

# Port-forward postgres for DBeaver (local)
kubectl port-forward svc/postgres-svc 5433:5432 -n atoloan-postgres

# SSH into AWS dev EC2
ssh -i ~/Downloads/atoloan-dev.pem ubuntu@3.135.161.145
```

## CoreDNS note (local only)

`k8s/coredns-patch.yaml` has hardcoded IPs that change on minikube restart:
- `10.109.229.89` → NGINX ingress ClusterIP
- `192.168.65.254` → `host.minikube.internal`

Re-check after restart:
```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}'
minikube ssh "cat /etc/hosts" | grep host.minikube.internal
```

## Task routing

| Task | Reference |
|---|---|
| Add a new microservice | `.claude/skills/atoloan-infra-engineer/references/new-service.md` |
| Add worker / CronJob / StatefulSet | `.claude/skills/atoloan-infra-engineer/references/workload-types.md` |
| Add Redis, SQS, SNS, RDS via Terraform | `.claude/skills/atoloan-infra-engineer/references/terraform-addons.md` |
| Debug pods, scale, rollback, logs | `.claude/skills/atoloan-infra-engineer/references/day2-ops.md` |
