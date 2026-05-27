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

# Both server and agent share the same profile (both need Secrets Manager access
# so External Secrets Operator, running on either node, can authenticate via IMDS)
resource "aws_iam_instance_profile" "atoloan_ec2_uat" {
  name = "atoloan-ec2-uat-profile"
  role = aws_iam_role.atoloan_ec2_uat.name
}
