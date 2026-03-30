# Day-2 Operations — atoloan

## Context setup

```bash
aws eks update-kubeconfig --name atoloan-cluster --region us-east-1
kubectl config current-context
```

---

## Debugging pods

```bash
kubectl get pods -n atoloan
kubectl describe pod <pod-name> -n atoloan
kubectl logs -n atoloan deployment/backend -f
kubectl logs -n atoloan <pod-name> --previous      # if pod restarted
kubectl exec -it <pod-name> -n atoloan -- /bin/bash
kubectl run debug --image=python:3.12-slim --rm -it --restart=Never -n atoloan -- /bin/bash
```

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ImagePullBackOff` | Wrong ECR URL or not authenticated | Check image name, re-run ECR login |
| `CrashLoopBackOff` | App crash on startup | `logs --previous`, check env vars |
| `OOMKilled` | Memory limit too low | Increase `resources.limits.memory` |
| `Pending` | No node capacity | `kubectl describe pod` → "Insufficient cpu/memory" |
| Readiness failing | `/health` not responding | Check probe config and app startup time |

---

## Scaling

```bash
kubectl scale deployment backend --replicas=4 -n atoloan
kubectl get hpa -n atoloan
kubectl patch hpa backend-hpa -n atoloan -p '{"spec":{"minReplicas":3,"maxReplicas":15}}'

# Scale EKS node group
aws eks update-nodegroup-config \
  --cluster-name atoloan-cluster --nodegroup-name atoloan-ng \
  --scaling-config minSize=2,maxSize=8,desiredSize=4 --region us-east-1
```

---

## Rolling updates & rollbacks

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

kubectl set image deployment/backend \
  backend=$AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/atoloan-backend:v1.2.3 -n atoloan

kubectl rollout status deployment/backend -n atoloan
kubectl rollout undo deployment/backend -n atoloan             # rollback
kubectl rollout history deployment/backend -n atoloan
kubectl rollout undo deployment/backend --to-revision=3 -n atoloan
```

---

## Secrets

```bash
kubectl get secret atoloan-secrets -n atoloan \
  -o jsonpath='{.data.database-url}' | base64 -d

kubectl patch secret atoloan-secrets -n atoloan \
  -p '{"stringData":{"new-key":"new-value"}}'

kubectl rollout restart deployment/backend -n atoloan   # pick up new secret values
```

---

## Database access

```bash
RDS_ENDPOINT=$(cd /Users/forumgandhi/atoloan-infra/infrastructure && terraform output -raw rds_endpoint)

kubectl run psql --image=postgres:15 --rm -it --restart=Never -n atoloan \
  --env="PGPASSWORD=<password>" \
  -- psql -h $RDS_ENDPOINT -U atoloan_admin -d atoloan_db

# Run Alembic migrations
DB_URL=$(kubectl get secret atoloan-secrets -n atoloan -o jsonpath='{.data.database-url}' | base64 -d)
kubectl run migrate --image=$AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/atoloan-backend:latest \
  --rm -it --restart=Never -n atoloan --env="DATABASE_URL=$DB_URL" \
  -- python -m alembic upgrade head
```

---

## Ingress / ALB

```bash
kubectl get ingress atoloan-ingress -n atoloan \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
kubectl describe ingress atoloan-ingress -n atoloan
kubectl logs -n kube-system deployment/aws-load-balancer-controller -f
```

---

## CronJobs

```bash
kubectl get cronjobs -n atoloan
kubectl create job --from=cronjob/atoloan-<task> atoloan-<task>-manual-$(date +%s) -n atoloan
kubectl logs -n atoloan -l job-name=atoloan-<task>-manual-<ts> -f
kubectl patch cronjob atoloan-<task> -n atoloan -p '{"spec":{"suspend":true}}'  # pause
```
