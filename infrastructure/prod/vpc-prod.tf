# ── VPC for prod environment ──────────────────────────────────────────────────
# CIDR 10.2.0.0/16 — intentionally different from UAT (10.1.0.0/16) and
# the default VPC used by dev, so there are no conflicts if VPCs are ever peered.

resource "aws_vpc" "atoloan_prod" {
  cidr_block           = "10.2.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "atoloan-prod-vpc"
    Environment = "prod"
    Project     = "atoloan"
  }
}

resource "aws_internet_gateway" "atoloan_prod" {
  vpc_id = aws_vpc.atoloan_prod.id

  tags = {
    Name        = "atoloan-prod-igw"
    Environment = "prod"
    Project     = "atoloan"
  }
}

# ── Public subnets (EC2) ──────────────────────────────────────────────────────

resource "aws_subnet" "atoloan_prod_public_a" {
  vpc_id                  = aws_vpc.atoloan_prod.id
  cidr_block              = "10.2.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "atoloan-prod-public-a"
    Environment = "prod"
    Project     = "atoloan"
  }
}

resource "aws_subnet" "atoloan_prod_public_b" {
  vpc_id                  = aws_vpc.atoloan_prod.id
  cidr_block              = "10.2.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true

  tags = {
    Name        = "atoloan-prod-public-b"
    Environment = "prod"
    Project     = "atoloan"
  }
}

# ── Private subnets (RDS) ─────────────────────────────────────────────────────

resource "aws_subnet" "atoloan_prod_private_a" {
  vpc_id            = aws_vpc.atoloan_prod.id
  cidr_block        = "10.2.10.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name        = "atoloan-prod-private-a"
    Environment = "prod"
    Project     = "atoloan"
  }
}

resource "aws_subnet" "atoloan_prod_private_b" {
  vpc_id            = aws_vpc.atoloan_prod.id
  cidr_block        = "10.2.11.0/24"
  availability_zone = "us-east-2b"

  tags = {
    Name        = "atoloan-prod-private-b"
    Environment = "prod"
    Project     = "atoloan"
  }
}

# ── Route table for public subnets ────────────────────────────────────────────

resource "aws_route_table" "atoloan_prod_public" {
  vpc_id = aws_vpc.atoloan_prod.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.atoloan_prod.id
  }

  tags = {
    Name        = "atoloan-prod-public-rt"
    Environment = "prod"
    Project     = "atoloan"
  }
}

resource "aws_route_table_association" "atoloan_prod_public_a" {
  subnet_id      = aws_subnet.atoloan_prod_public_a.id
  route_table_id = aws_route_table.atoloan_prod_public.id
}

resource "aws_route_table_association" "atoloan_prod_public_b" {
  subnet_id      = aws_subnet.atoloan_prod_public_b.id
  route_table_id = aws_route_table.atoloan_prod_public.id
}
