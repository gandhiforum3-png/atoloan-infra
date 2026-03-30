# Terraform Add-ons — New AWS Resources for atoloan

---

## ElastiCache Redis

```hcl
# infrastructure/elasticache.tf
resource "aws_elasticache_subnet_group" "atoloan" {
  name       = "atoloan-redis-subnets"
  subnet_ids = module.vpc.private_subnets
}
resource "aws_security_group" "redis" {
  name   = "atoloan-redis-sg"
  vpc_id = module.vpc.vpc_id
  ingress {
    from_port       = 6379; to_port = 6379; protocol = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}
resource "aws_elasticache_replication_group" "atoloan" {
  replication_group_id       = "atoloan-redis"
  description                = "atoloan Redis cache"
  node_type                  = "cache.t3.micro"
  num_cache_clusters         = 2
  automatic_failover_enabled = true
  port                       = 6379
  parameter_group_name       = "default.redis7"
  subnet_group_name          = aws_elasticache_subnet_group.atoloan.name
  security_group_ids         = [aws_security_group.redis.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  tags = { Project = "atoloan" }
}
output "redis_endpoint" {
  value     = aws_elasticache_replication_group.atoloan.primary_endpoint_address
  sensitive = true
}
```

---

## SQS Queue

```hcl
# infrastructure/sqs.tf
resource "aws_sqs_queue" "atoloan_<queue>" {
  name                       = "atoloan-<queue>"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20   # long polling
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.atoloan_<queue>_dlq.arn
    maxReceiveCount     = 3
  })
  tags = { Project = "atoloan" }
}
resource "aws_sqs_queue" "atoloan_<queue>_dlq" {
  name                      = "atoloan-<queue>-dlq"
  message_retention_seconds = 1209600
  tags = { Project = "atoloan", Type = "DLQ" }
}
output "<queue>_url" { value = aws_sqs_queue.atoloan_<queue>.url }
```

**IAM policy for the consumer pod:**
```hcl
{ Effect = "Allow"
  Action = ["sqs:ReceiveMessage","sqs:DeleteMessage","sqs:GetQueueAttributes","sqs:ChangeMessageVisibility"]
  Resource = aws_sqs_queue.atoloan_<queue>.arn }
```

---

## SNS Topic

```hcl
# infrastructure/sns.tf
resource "aws_sns_topic" "atoloan_<topic>" {
  name = "atoloan-<topic>"
  tags = { Project = "atoloan" }
}
resource "aws_sns_topic_subscription" "atoloan_<topic>_to_<queue>" {
  topic_arn = aws_sns_topic.atoloan_<topic>.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.atoloan_<queue>.arn
}
resource "aws_sqs_queue_policy" "atoloan_<queue>_sns" {
  queue_url = aws_sqs_queue.atoloan_<queue>.url
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.atoloan_<queue>.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.atoloan_<topic>.arn } }
    }]
  })
}
output "<topic>_arn" { value = aws_sns_topic.atoloan_<topic>.arn }
```

---

## AWS Secrets Manager

```hcl
# infrastructure/secrets.tf
resource "aws_secretsmanager_secret" "atoloan_<secret>" {
  name                    = "atoloan/<secret>"
  recovery_window_in_days = 7
  tags = { Project = "atoloan" }
}
resource "aws_secretsmanager_secret_version" "atoloan_<secret>" {
  secret_id     = aws_secretsmanager_secret.atoloan_<secret>.id
  secret_string = jsonencode({ key = "value" })
}
```

**IAM policy to read from a pod:**
```hcl
{ Effect = "Allow", Action = ["secretsmanager:GetSecretValue"],
  Resource = aws_secretsmanager_secret.atoloan_<secret>.arn }
```

---

## Additional RDS instance (per-service DB)

```hcl
# infrastructure/rds-<service>.tf
resource "aws_db_instance" "atoloan_<service>" {
  identifier     = "atoloan-<service>-postgres"
  engine         = "postgres"; engine_version = "15.4"
  instance_class = "db.t3.small"
  allocated_storage = 20; storage_encrypted = true
  db_name  = "atoloan_<service>_db"
  username = "atoloan_<service>_admin"
  password = var.<service>_db_password
  db_subnet_group_name   = aws_db_subnet_group.atoloan.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az = true; publicly_accessible = false
  backup_retention_period = 7; deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "atoloan-<service>-postgres-final"
  tags = { Project = "atoloan", Service = "<service>" }
}
```
