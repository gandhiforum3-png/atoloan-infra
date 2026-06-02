# ── RDS Security Group ────────────────────────────────────────────────────────

resource "aws_security_group" "atoloan_rds_prod" {
  name        = "atoloan-rds-prod-sg"
  description = "Allow PostgreSQL from k3s prod nodes only"
  vpc_id      = aws_vpc.atoloan_prod.id

  ingress {
    description     = "PostgreSQL from k3s nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.atoloan_k8s_prod.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "atoloan-rds-prod-sg"
    Environment = "prod"
    Project     = "atoloan"
  }
}

# ── DB Subnet Group ───────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "atoloan_prod" {
  name = "atoloan-prod-db-subnet-group"
  subnet_ids = [
    aws_subnet.atoloan_prod_private_a.id,
    aws_subnet.atoloan_prod_private_b.id,
  ]

  tags = {
    Name        = "atoloan-prod-db-subnet-group"
    Environment = "prod"
    Project     = "atoloan"
  }
}

# ── Random password for RDS master user ───────────────────────────────────────

resource "random_password" "atoloan_rds_prod" {
  length           = 24
  special          = true
  override_special = "!#$%&*-_=+[]<>:?"
}

# ── RDS PostgreSQL 16 (db.t4g.micro, single-AZ) ──────────────────────────────

resource "aws_db_instance" "atoloan_postgres_prod" {
  identifier        = "atoloan-postgres-prod"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = "db.t4g.micro"
  allocated_storage = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "atoloandb"
  username = "atoloanuser"
  password = random_password.atoloan_rds_prod.result

  db_subnet_group_name   = aws_db_subnet_group.atoloan_prod.name
  vpc_security_group_ids = [aws_security_group.atoloan_rds_prod.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = 0
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Enabled for prod — prevents accidental terraform destroy from wiping the DB
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "atoloan-postgres-prod-final-snapshot"

  tags = {
    Name        = "atoloan-postgres-prod"
    Environment = "prod"
    Project     = "atoloan"
  }
}
