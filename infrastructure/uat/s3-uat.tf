# ── S3 bucket for user-uploaded documents (driver's license, paycheck) ────────

resource "aws_s3_bucket" "atoloan_user_documents_uat" {
  bucket = "atoloan-user-documents-uat"

  tags = {
    Name        = "atoloan-user-documents-uat"
    Environment = "uat"
    Project     = "atoloan"
  }
}

resource "aws_s3_bucket_public_access_block" "atoloan_user_documents_uat" {
  bucket = aws_s3_bucket.atoloan_user_documents_uat.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "atoloan_user_documents_uat" {
  bucket = aws_s3_bucket.atoloan_user_documents_uat.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "atoloan_user_documents_uat" {
  bucket = aws_s3_bucket.atoloan_user_documents_uat.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "atoloan_user_documents_uat" {
  bucket = aws_s3_bucket.atoloan_user_documents_uat.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.atoloan_user_documents_uat.arn,
        "${aws_s3_bucket.atoloan_user_documents_uat.arn}/*"
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.atoloan_user_documents_uat]
}

output "user_documents_bucket_uat" {
  value = aws_s3_bucket.atoloan_user_documents_uat.bucket
}
