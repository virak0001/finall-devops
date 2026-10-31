# DNS and HTTPS — the public name and the certificate for it.
#
#   dev.devops-selft-learning.xyz ─ALIAS─► ALB :443 ─► pod
#                                  ▲        ▲
#                       external-dns   AWS Load Balancer Controller
#
# Off unless var.dns_zone_name and var.site_hostname are both set.
#
# Terraform owns the certificate, not the record. The ALB is created by the
# load balancer controller from an Ingress, so Terraform never learns its
# address; external-dns, which watches that Ingress, writes the alias record
# instead (its permissions are module.eks.pod_identities["external-dns"]).
# The controller picks this certificate up on its own, by matching the
# Ingress host against the certificates in the account.
#
# The hosted zone is READ, not managed. Delegation lives at the registrar, so a
# zone destroyed by `make destroy` would take its NS records with it and leave
# the domain dark until those four nameservers were pasted back by hand.

locals {
  dns_enabled = var.dns_zone_name != "" && var.site_hostname != ""

  site_hostnames = local.dns_enabled ? distinct(concat([var.site_hostname], var.site_aliases)) : []

  # The wildcard covers one level below the site — argocd.dev.example.com —
  # which is where admin UIs go, so each does not need a certificate of its own.
  certificate_names = local.dns_enabled ? distinct(concat(local.site_hostnames, ["*.${var.site_hostname}"])) : []

  site_url = local.dns_enabled ? "https://${var.site_hostname}" : null
}

data "aws_route53_zone" "this" {
  count = var.dns_zone_name != "" ? 1 : 0

  name         = "${var.dns_zone_name}."
  private_zone = false
}

resource "terraform_data" "hostname_in_zone" {
  count = local.dns_enabled ? 1 : 0

  lifecycle {
    precondition {
      condition = alltrue([
        for h in local.site_hostnames :
        h == var.dns_zone_name || endswith(h, ".${var.dns_zone_name}")
      ])
      error_message = "Every site hostname must be ${var.dns_zone_name} or a name under it."
    }
  }
}

# ─── Certificate ─────────────────────────────────────────────────────────────
# Free, and renewed by ACM for as long as the validation record below stays in
# the zone. Validated over DNS rather than email, so nobody has to click a link.

resource "aws_acm_certificate" "site" {
  count = local.dns_enabled ? 1 : 0

  domain_name               = var.site_hostname
  subject_alternative_names = slice(local.certificate_names, 1, length(local.certificate_names))
  validation_method         = "DNS"

  tags = { Name = var.site_hostname }

  # An ALB still holds the old certificate while the new one is issued. The
  # other order fails with ResourceInUseException.
  lifecycle {
    create_before_destroy = true
  }
}

# Keyed by the hostnames in config, not by domain_validation_options, whose
# contents are only known once ACM has answered — for_each has to know every
# key at plan time. The record for each name is looked up from it at apply.
#
# The wildcard is left out because *.dev.example.com validates with the SAME
# record as dev.example.com; a second entry would write the same name twice.
#
# allow_overwrite adopts a validation record left in the zone by an earlier
# certificate for the same name, instead of failing on it.
locals {
  validated_names = toset([for n in local.certificate_names : n if !startswith(n, "*.")])
}

resource "aws_route53_record" "certificate_validation" {
  for_each = local.validated_names

  zone_id         = data.aws_route53_zone.this[0].zone_id
  name            = local.validation_options[each.key].resource_record_name
  type            = local.validation_options[each.key].resource_record_type
  records         = [local.validation_options[each.key].resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

locals {
  validation_options = local.dns_enabled ? {
    for o in aws_acm_certificate.site[0].domain_validation_options : o.domain_name => o
  } : {}
}

# Waits until ACM says ISSUED, so nothing downstream gets a PENDING certificate
# an ALB would refuse. Usually 2-5 minutes after the record lands.
resource "aws_acm_certificate_validation" "site" {
  count = local.dns_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.site[0].arn
  validation_record_fqdns = [for r in aws_route53_record.certificate_validation : r.fqdn]
}
