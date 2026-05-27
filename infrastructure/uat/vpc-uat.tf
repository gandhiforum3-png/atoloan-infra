# ── VPC for UAT environment ───────────────────────────────────────────────────
# Dedicated VPC so UAT is fully isolated from dev.
# Layout:
#   Public subnets  (2a, 2b) → k3s EC2 instances
#   Private subnets (2a, 2b) → RDS (AWS requires 2 AZs for a DB subnet group)

resource "aws_vpc" "atoloan_uat" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "atoloan-uat-vpc"
    Environment = "uat"
    Project     = "atoloan"
  }
}

resource "aws_internet_gateway" "atoloan_uat" {
  vpc_id = aws_vpc.atoloan_uat.id

  tags = {
    Name        = "atoloan-uat-igw"
    Environment = "uat"
    Project     = "atoloan"
  }
}

# ── Public subnets (EC2) ──────────────────────────────────────────────────────

resource "aws_subnet" "atoloan_uat_public_a" {
  vpc_id                  = aws_vpc.atoloan_uat.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "atoloan-uat-public-a"
    Environment = "uat"
    Project     = "atoloan"
  }
}

resource "aws_subnet" "atoloan_uat_public_b" {
  vpc_id                  = aws_vpc.atoloan_uat.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true

  tags = {
    Name        = "atoloan-uat-public-b"
    Environment = "uat"
    Project     = "atoloan"
  }
}

# ── Private subnets (RDS) ─────────────────────────────────────────────────────

resource "aws_subnet" "atoloan_uat_private_a" {
  vpc_id            = aws_vpc.atoloan_uat.id
  cidr_block        = "10.1.10.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name        = "atoloan-uat-private-a"
    Environment = "uat"
    Project     = "atoloan"
  }
}

resource "aws_subnet" "atoloan_uat_private_b" {
  vpc_id            = aws_vpc.atoloan_uat.id
  cidr_block        = "10.1.11.0/24"
  availability_zone = "us-east-2b"

  tags = {
    Name        = "atoloan-uat-private-b"
    Environment = "uat"
    Project     = "atoloan"
  }
}

# ── Route table for public subnets ────────────────────────────────────────────
# Private subnets intentionally have no route to IGW — RDS does not need internet.

resource "aws_route_table" "atoloan_uat_public" {
  vpc_id = aws_vpc.atoloan_uat.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.atoloan_uat.id
  }

  tags = {
    Name        = "atoloan-uat-public-rt"
    Environment = "uat"
    Project     = "atoloan"
  }
}

resource "aws_route_table_association" "atoloan_uat_public_a" {
  subnet_id      = aws_subnet.atoloan_uat_public_a.id
  route_table_id = aws_route_table.atoloan_uat_public.id
}

resource "aws_route_table_association" "atoloan_uat_public_b" {
  subnet_id      = aws_subnet.atoloan_uat_public_b.id
  route_table_id = aws_route_table.atoloan_uat_public.id
}
