# ── Secrets Manager: RDS credentials for UAT ─────────────────────────────────
# Terraform writes the RDS endpoint + credentials here automatically after
# the RDS instance is created. The k3s cluster reads this via ExternalSecret.

resource "aws_secretsmanager_secret" "atoloan_postgres_uat" {
  name        = "atoloan/postgres-uat"
  description = "PostgreSQL credentials for atoloan UAT (managed by Terraform)"

  tags = {
    Environment = "uat"
    Project     = "atoloan"
  }
}

resource "aws_secretsmanager_secret_version" "atoloan_postgres_uat" {
  secret_id = aws_secretsmanager_secret.atoloan_postgres_uat.id

  secret_string = jsonencode({
    PGUSER     = aws_db_instance.atoloan_postgres_uat.username
    PGPASSWORD = random_password.atoloan_rds_uat.result
    PGDATABASE = aws_db_instance.atoloan_postgres_uat.db_name
    # address = hostname only (no port) — port is stored separately
    PGHOST = aws_db_instance.atoloan_postgres_uat.address
    PGPORT = tostring(aws_db_instance.atoloan_postgres_uat.port)
  })
}
