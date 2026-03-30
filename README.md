# atoloan-infra
All infrastructure level code and configs


## Get postgres backup
kubectl exec -n default $(kubectl get pod -n default -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- pg_dumpall -U atoloanuser > postgres-backup.sql  
## Postgres user 
kubectl get secret postgres-secret -n default -o jsonpath='{.data.POSTGRES_USER}' | base64 --decode