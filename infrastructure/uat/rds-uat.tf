# ── RDS Security Group ────────────────────────────────────────────────────────
# Only allows port 5432 from the k3s nodes SG — not publicly accessible.

resource "aws_security_group" "atoloan_rds_uat" {
  name        = "atoloan-rds-uat-sg"
  description = "Allow PostgreSQL from k3s UAT nodes only"
  vpc_id      = aws_vpc.atoloan_uat.id

  ingress {
    description     = "PostgreSQL from k3s nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.atoloan_k8s_uat.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "atoloan-rds-uat-sg"
    Environment = "uat"
    Project     = "atoloan"
  }
}

# ── DB Subnet Group ───────────────────────────────────────────────────────────
# AWS requires at least 2 subnets in different AZs for a DB subnet group,
# even for single-AZ instances.

resource "aws_db_subnet_group" "atoloan_uat" {
  name = "atoloan-uat-db-subnet-group"
  subnet_ids = [
    aws_subnet.atoloan_uat_private_a.id,
    aws_subnet.atoloan_uat_private_b.id,
  ]

  tags = {
    Name        = "atoloan-uat-db-subnet-group"
    Environment = "uat"
    Project     = "atoloan"
  }
}

# ── Random password for RDS master user ───────────────────────────────────────

resource "random_password" "atoloan_rds_uat" {
  length           = 24
  special          = true
  override_special = "!#$%&*-_=+[]<>:?"
}

# ── RDS PostgreSQL 16 (db.t4g.micro, single-AZ) ──────────────────────────────
# Data survives EC2 stop/start because it lives on RDS-managed EBS storage,
# independent of the k3s cluster. Automated backups retain 7 days.

resource "aws_db_instance" "atoloan_postgres_uat" {
  identifier        = "atoloan-postgres-uat"
  engine            = "postgres"
  engine_version    = "16"   # AWS will use latest 16.x; pin to e.g. "16.3" if needed
  instance_class    = "db.t4g.micro"
  allocated_storage = 20
  # Auto-scales up to 100 GB if the DB grows — no manual intervention needed
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "atoloandb"
  username = "atoloanuser"
  password = random_password.atoloan_rds_uat.result

  db_subnet_group_name   = aws_db_subnet_group.atoloan_uat.name
  vpc_security_group_ids = [aws_security_group.atoloan_rds_uat.id]
  publicly_accessible    = false
  multi_az               = false

  # Free tier restricts backup retention to 0 (no automated snapshots).
  # Data is still preserved across stops/restarts — it lives on RDS-managed EBS,
  # not in the k3s cluster. Set to 7 if you upgrade to a paid account.
  backup_retention_period = 0
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Set deletion_protection = true once UAT is stabilized to prevent accidents
  deletion_protection       = false
  skip_final_snapshot       = false
  final_snapshot_identifier = "atoloan-postgres-uat-final-snapshot"

  tags = {
    Name        = "atoloan-postgres-uat"
    Environment = "uat"
    Project     = "atoloan"
  }
}
