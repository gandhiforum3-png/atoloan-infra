# ── DNS records for prod (written into the shared Route 53 zone) ──────────────
# The zone itself lives in infrastructure/dns/ and is looked up via data source
# in provider.tf. These records are owned by the prod module — they are created
# on terraform apply and removed on terraform destroy. The zone survives.

# atoloans.com → prod server (frontend)
resource "aws_route53_record" "atoloans_root" {
  zone_id = data.aws_route53_zone.atoloans.zone_id
  name    = "atoloans.com"
  type    = "A"
  ttl     = 300
  records = [aws_eip.atoloan_k8s_prod.public_ip]
}

# www.atoloans.com → atoloans.com redirect (CNAME)
resource "aws_route53_record" "atoloans_www" {
  zone_id = data.aws_route53_zone.atoloans.zone_id
  name    = "www.atoloans.com"
  type    = "CNAME"
  ttl     = 300
  records = ["atoloans.com"]
}

# api.atoloans.com → prod server (backend)
resource "aws_route53_record" "atoloans_api" {
  zone_id = data.aws_route53_zone.atoloans.zone_id
  name    = "api.atoloans.com"
  type    = "A"
  ttl     = 300
  records = [aws_eip.atoloan_k8s_prod.public_ip]
}

# postgres.atoloans.com → RDS endpoint (CNAME alias)
# If RDS is ever recreated, update only this record — nothing else changes.
resource "aws_route53_record" "atoloans_postgres" {
  zone_id = data.aws_route53_zone.atoloans.zone_id
  name    = "postgres.atoloans.com"
  type    = "CNAME"
  ttl     = 300
  records = [aws_db_instance.atoloan_postgres_prod.address]
}
