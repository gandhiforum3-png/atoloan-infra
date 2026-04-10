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

resource "aws_iam_instance_profile" "atoloan_ec2_dev" {
  name = "atoloan-ec2-dev-profile"
  role = aws_iam_role.atoloan_ec2_dev.name
}
