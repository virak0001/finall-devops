# Platform facts — the handover to the cluster project, published to SSM.
#
#   /platform/dev/cluster_name   upskill-devops-dev
#   /platform/dev/vpc_id         vpc-0abc…
#   …
#
# The cluster project reads these with scripts/platform.sh, layer 4:
#
#   PLATFORM_SSM_PREFIX=/platform make <target> WORKSPACE=dev
#
# They used to be pasted by hand from `terraform output` into
# cluster/platform/<ws>.env, which went stale on every apply that moved an
# address — the bastion, the control plane and the ALB all drifted at once in
# September. Written here, they change in the same apply that changes them.
#
# The cluster project needs only ssm:GetParameter on this path: no Terraform,
# no state, no checkout of this repo. Standard-tier parameters are free.

locals {
  ecr_registry_url = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  ecr_image_prefix = "${local.ecr_registry_url}/upskill-devops"

  # Inclusion is decided by variables only. Filtering on the values instead —
  # dropping empty ones — would make the key set depend on attributes unknown
  # until apply, and for_each refuses to plan that.
  platform_facts = merge(
    {
      region           = var.region
      cluster_name     = module.eks.cluster_name
      vpc_id           = module.network.vpc_id
      ecr_registry_url = local.ecr_registry_url
      ecr_image_prefix = local.ecr_image_prefix

      lbc_role_arn = module.eks.pod_identities["aws-load-balancer-controller"].role_arn

      # Comma-separated, because a String parameter is one line. The team
      # NetworkPolicies admit traffic from these: with target-type ip the ALB
      # connects to pods directly, from addresses in the public subnets.
      public_subnet_cidrs = join(",", module.network.public_subnet_cidrs)

      # A team's secret is <secrets_name_prefix>/<team>, read through the role
      # <secrets_role_prefix><team>.
      secrets_name_prefix = local.secrets_name_prefix
      secrets_role_prefix = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.secrets_role_prefix}"
    },
    # The WAF web ACL (module.waf, main.tf). The cluster project annotates every Ingress
    # in the ALB group with it, and the Load Balancer Controller attaches it.
    var.waf_enabled ? {
      waf_acl_arn = module.waf[0].web_acl_arn
    } : {},
    # The bucket the Ingresses point the ALB's access logs at (module.monitoring).
    var.enable_monitoring && var.alb_access_logs ? {
      alb_logs_bucket = module.monitoring[0].alb_logs_bucket
    } : {},
    local.dns_enabled ? {
      site_url        = local.site_url
      site_hostname   = var.site_hostname
      certificate_arn = aws_acm_certificate_validation.site[0].certificate_arn
      route53_zone_id = data.aws_route53_zone.this[0].zone_id
    } : {},
  )
}

resource "aws_ssm_parameter" "platform" {
  for_each = local.platform_facts

  name  = "${var.platform_ssm_prefix}/${local.environment}/${each.key}"
  type  = "String"
  value = each.value

  tags = var.tags
}
