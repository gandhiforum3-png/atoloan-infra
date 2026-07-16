resource "aws_iam_role" "atoloan_ec2_uat" {
  name = "atoloan-ec2-uat-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "atoloan_ec2_uat_secrets" {
  name = "atoloan-ec2-uat-secrets-policy"
  role = aws_iam_role.atoloan_ec2_uat.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecrets"
      ]
      # Grants access to all atoloan/* secrets — same scope as dev
      Resource = "arn:aws:secretsmanager:us-east-2:*:secret:atoloan/*"
    }]
  })
}

resource "aws_iam_role_policy" "atoloan_ec2_uat_s3_documents" {
  name = "atoloan-ec2-uat-s3-documents-policy"
  role = aws_iam_role.atoloan_ec2_uat.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::atoloan-user-documents-uat/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::atoloan-user-documents-uat"
      }
    ]
  })
}

# Both server and agent share the same profile (both need Secrets Manager access
# so External Secrets Operator, running on either node, can authenticate via IMDS)
resource "aws_iam_instance_profile" "atoloan_ec2_uat" {
  name = "atoloan-ec2-uat-profile"
  role = aws_iam_role.atoloan_ec2_uat.name
}
