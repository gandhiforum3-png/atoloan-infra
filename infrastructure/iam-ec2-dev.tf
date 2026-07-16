resource "aws_iam_role" "atoloan_ec2_dev" {
  name = "atoloan-ec2-dev-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "atoloan_ec2_dev_secrets" {
  name = "atoloan-ec2-dev-secrets-policy"
  role = aws_iam_role.atoloan_ec2_dev.id

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

resource "aws_iam_role_policy" "atoloan_ec2_dev_s3_documents" {
  name = "atoloan-ec2-dev-s3-documents-policy"
  role = aws_iam_role.atoloan_ec2_dev.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::atoloan-user-documents-dev/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::atoloan-user-documents-dev"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "atoloan_ec2_dev" {
  name = "atoloan-ec2-dev-profile"
  role = aws_iam_role.atoloan_ec2_dev.name
}
