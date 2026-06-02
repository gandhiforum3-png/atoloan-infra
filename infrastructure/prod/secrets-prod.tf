# ── Secrets Manager: RDS credentials for prod ────────────────────────────────
# PGHOST is set to the Route 53 CNAME alias (postgres.atoloans.com) rather than
# the raw RDS endpoint. If RDS is ever recreated, only the CNAME needs updating —
# the secret, the k8s ExternalSecret, and the application config stay unchanged.

resource "aws_secretsmanager_secret" "atoloan_postgres_prod" {
  name        = "atoloan/postgres-prod"
  description = "PostgreSQL credentials for atoloan prod (managed by Terraform)"

  tags = {
    Environment = "prod"
    Project     = "atoloan"
  }
}

resource "aws_secretsmanager_secret_version" "atoloan_postgres_prod" {
  secret_id = aws_secretsmanager_secret.atoloan_postgres_prod.id

  secret_string = jsonencode({
    PGUSER     = aws_db_instance.atoloan_postgres_prod.username
    PGPASSWORD = random_password.atoloan_rds_prod.result
    PGDATABASE = aws_db_instance.atoloan_postgres_prod.db_name
    PGHOST     = "postgres.atoloans.com"   # CNAME alias — never changes
    PGPORT     = tostring(aws_db_instance.atoloan_postgres_prod.port)
  })
}
