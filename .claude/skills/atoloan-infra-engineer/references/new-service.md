# Adding a New Service to atoloan

Use this when the user wants to add a new microservice, API, or any new container-based workload.
Follow these steps in order — check what exists first, then generate what's missing.

## Step 1: Decide the service type

| Type | K8s kind | Use when |
|------|----------|----------|
| API / HTTP service | `Deployment` + `Service` + Ingress route | Serves HTTP requests |
| Background worker | `Deployment` (no Service) | Processes queues, events |
| Scheduled task | `CronJob` | Runs on a cron schedule |
| Stateful service | `StatefulSet` | Needs stable storage (e.g. custom DB) |

For workers and CronJobs, see `references/workload-types.md`.

## Step 2: Dockerfile for the new service

### FastAPI service
```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpq-dev && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --upgrade pip && pip install --prefix=/install --no-cache-dir -r requirements.txt

FROM python:3.12-slim AS runtime
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends libpq5 curl && rm -rf /var/lib/apt/lists/*
COPY --from=builder /install /usr/local
COPY . .
RUN adduser --disabled-password --gecos "" atoloan && chown -R atoloan:atoloan /app
USER atoloan
EXPOSE <PORT>
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -sf http://localhost:<PORT>/health || exit 1
CMD ["gunicorn", "main:app", "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--workers", "4", "--bind", "0.0.0.0:<PORT>", "--timeout", "120", "--access-logfile", "-"]
```

### Node.js service
```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --silent
COPY . .
RUN npm run build 2>/dev/null || true

FROM node:20-alpine AS runtime
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json .
RUN adduser -D -H -u 1000 atoloan && chown -R atoloan:atoloan /app
USER atoloan
EXPOSE <PORT>
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD wget -qO- http://localhost:<PORT>/health || exit 1
CMD ["node", "dist/index.js"]
```

Place Dockerfile at `/<service-name>/Dockerfile` in the repo root.

## Step 3: ECR repository (Terraform)

Add to `infrastructure/ecr.tf` (create if missing):
```hcl
resource "aws_ecr_repository" "atoloan_<service>" {
  name                 = "atoloan-<service>"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = { Project = "atoloan", Service = "<service>" }
}
```

## Step 4: IAM role for the pod (only if it needs AWS access)

Add to `infrastructure/iam.tf`:
```hcl
resource "aws_iam_role" "<service>" {
  name = "atoloan-<service>-pod-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "${module.eks.oidc_provider}:sub" = "system:serviceaccount:atoloan:<service>-sa"
      }}
    }]
  })
}
resource "aws_iam_policy" "<service>_policy" {
  name   = "atoloan-<service>-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [ /* add only permissions this service needs */ ]
  })
}
resource "aws_iam_role_policy_attachment" "<service>" {
  role       = aws_iam_role.<service>.name
  policy_arn = aws_iam_policy.<service>_policy.arn
}
```

## Step 5: Kubernetes manifests → `k8s/<service>/`

### serviceaccount.yaml (only if the pod needs AWS access)
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: <service>-sa
  namespace: atoloan
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::<AWS_ACCOUNT_ID>:role/atoloan-<service>-pod-role"
  labels:
    app: atoloan-<service>
```

### deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <service>
  namespace: atoloan
  labels:
    app: atoloan-<service>
spec:
  replicas: 2
  selector:
    matchLabels:
      app: atoloan-<service>
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxSurge: 1, maxUnavailable: 0 }
  template:
    metadata:
      labels:
        app: atoloan-<service>
    spec:
      serviceAccountName: <service>-sa
      containers:
        - name: <service>
          image: <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/atoloan-<service>:latest
          imagePullPolicy: Always
          ports:
            - containerPort: <PORT>
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: atoloan-secrets
                  key: database-url
            - name: ENVIRONMENT
              value: production
          resources:
            requests: { cpu: "250m", memory: "256Mi" }
            limits:   { cpu: "500m", memory: "512Mi" }
          livenessProbe:
            httpGet: { path: /health, port: <PORT> }
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet: { path: /health, port: <PORT> }
            initialDelaySeconds: 10
            periodSeconds: 5
```

### service.yaml (HTTP services only)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: <service>-svc
  namespace: atoloan
spec:
  type: ClusterIP
  selector:
    app: atoloan-<service>
  ports:
    - port: 80
      targetPort: <PORT>
```

### hpa.yaml
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: <service>-hpa
  namespace: atoloan
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: <service>
  minReplicas: 2
  maxReplicas: 8
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: { type: Utilization, averageUtilization: 70 }
```

## Step 6: Add ingress route (HTTP services only)

Edit `k8s/ingress.yaml` — add before the catch-all `/` path:
```yaml
- path: /<service>
  pathType: Prefix
  backend:
    service:
      name: <service>-svc
      port: { number: 80 }
```

## Deploy
```bash
# 1. Terraform (if ECR repo or IAM role added)
cd /Users/forumgandhi/atoloan-infra/infrastructure && terraform plan && terraform apply

# 2. Build & push
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
docker build -t atoloan-<service> ./<service>/
docker tag atoloan-<service>:latest $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/atoloan-<service>:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/atoloan-<service>:latest

# 3. Deploy
kubectl apply -f k8s/<service>/
kubectl apply -f k8s/ingress.yaml
kubectl rollout status deployment/<service> -n atoloan
```
