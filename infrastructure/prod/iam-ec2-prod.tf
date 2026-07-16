resource "aws_iam_role" "atoloan_ec2_prod" {
  name = "atoloan-ec2-prod-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "atoloan_ec2_prod_secrets" {
  name = "atoloan-ec2-prod-secrets-policy"
  role = aws_iam_role.atoloan_ec2_prod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecrets"
      ]
      Resource = "arn:aws:secretsmanager:us-east-2:*:secret:atoloan/*"
    }]
  })
}

resource "aws_iam_role_policy" "atoloan_ec2_prod_s3_documents" {
  name = "atoloan-ec2-prod-s3-documents-policy"
  role = aws_iam_role.atoloan_ec2_prod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::atoloan-user-documents-prod/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::atoloan-user-documents-prod"
      }
    ]
  })
}

# Both server and agent share the same profile — both nodes need Secrets Manager
# access so External Secrets Operator can authenticate via IMDS on either node
resource "aws_iam_instance_profile" "atoloan_ec2_prod" {
  name = "atoloan-ec2-prod-profile"
  role = aws_iam_role.atoloan_ec2_prod.name
}
