# Workload Types — atoloan

## Worker (background processor — no HTTP port)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <service>-worker
  namespace: atoloan
  labels:
    app: atoloan-<service>-worker
spec:
  replicas: 2
  selector:
    matchLabels:
      app: atoloan-<service>-worker
  template:
    metadata:
      labels:
        app: atoloan-<service>-worker
    spec:
      serviceAccountName: <service>-sa
      containers:
        - name: worker
          image: <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/atoloan-<service>-worker:latest
          imagePullPolicy: Always
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: atoloan-secrets
                  key: database-url
            - name: QUEUE_URL
              valueFrom:
                secretKeyRef:
                  name: atoloan-secrets
                  key: <queue>-url
          resources:
            requests: { cpu: "250m", memory: "256Mi" }
            limits:   { cpu: "1000m", memory: "512Mi" }
          livenessProbe:
            exec:
              command: ["python", "-c", "import sys; sys.exit(0)"]
            initialDelaySeconds: 30
            periodSeconds: 30
```

**Python worker Dockerfile (no HTTP server):**
```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpq-dev && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --prefix=/install --no-cache-dir -r requirements.txt

FROM python:3.12-slim AS runtime
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends libpq5 && rm -rf /var/lib/apt/lists/*
COPY --from=builder /install /usr/local
COPY . .
RUN adduser --disabled-password --gecos "" atoloan && chown -R atoloan:atoloan /app
USER atoloan
CMD ["python", "-m", "worker.main"]
```

---

## CronJob (scheduled task)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: atoloan-<task>
  namespace: atoloan
spec:
  schedule: "0 2 * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          serviceAccountName: <service>-sa
          restartPolicy: OnFailure
          containers:
            - name: <task>
              image: <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/atoloan-<task>:latest
              imagePullPolicy: Always
              env:
                - name: DATABASE_URL
                  valueFrom:
                    secretKeyRef:
                      name: atoloan-secrets
                      key: database-url
              resources:
                requests: { cpu: "250m", memory: "256Mi" }
                limits:   { cpu: "500m", memory: "512Mi" }
              command: ["python", "-m", "tasks.<task>"]
```

**Cron expressions:**
```
"0 * * * *"      every hour
"*/15 * * * *"   every 15 min
"0 2 * * *"      daily 2am UTC
"0 2 * * 0"      weekly Sunday 2am
"0 0 1 * *"      monthly
```

**Trigger a CronJob manually:**
```bash
kubectl create job --from=cronjob/atoloan-<task> atoloan-<task>-manual -n atoloan
kubectl logs -l job-name=atoloan-<task>-manual -n atoloan -f
```

---

## StatefulSet

Only use when a managed AWS service isn't available. Prefer RDS, ElastiCache, SQS.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: atoloan-<service>
  namespace: atoloan
spec:
  serviceName: "<service>"
  replicas: 1
  selector:
    matchLabels:
      app: atoloan-<service>
  template:
    metadata:
      labels:
        app: atoloan-<service>
    spec:
      containers:
        - name: <service>
          image: <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/atoloan-<service>:latest
          ports:
            - containerPort: <PORT>
          volumeMounts:
            - name: data
              mountPath: /data
          resources:
            requests: { cpu: "250m", memory: "512Mi" }
            limits:   { cpu: "500m", memory: "1Gi" }
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp2
        resources:
          requests:
            storage: 20Gi
```

---

## ConfigMap (non-sensitive config)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: atoloan-<service>-config
  namespace: atoloan
data:
  LOG_LEVEL: "INFO"
  WORKERS: "4"
```

Reference in pod: `envFrom: - configMapRef: { name: atoloan-<service>-config }`
