# ── Route 53 Hosted Zone for atoloans.com ────────────────────────────────────
# This module is intentionally separate from prod so the DNS zone and all
# records survive even if infrastructure/prod/ is torn down and rebuilt.
#
# HOW TO USE:
#   1. cd infrastructure/dns/ && terraform init && terraform apply
#   2. Copy the 4 nameservers from the output below
#   3. In GoDaddy: My Products → DNS → atoloans.com → Nameservers → Custom
#      Paste the 4 nameservers — DNS propagation takes up to 48 hours
#   4. Then deploy infrastructure/prod/ — it will add A records to this zone

resource "aws_route53_zone" "atoloans" {
  name = "atoloans.com"

  tags = {
    Name    = "atoloans-zone"
    Project = "atoloan"
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "zone_id" {
  description = "Route 53 hosted zone ID — referenced by infrastructure/prod/"
  value       = aws_route53_zone.atoloans.zone_id
}

output "nameservers" {
  description = "Add these 4 nameservers in GoDaddy under Custom Nameservers"
  value       = aws_route53_zone.atoloans.name_servers
}
