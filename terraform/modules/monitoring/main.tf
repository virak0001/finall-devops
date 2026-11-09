# Monitoring module — what one environment needs so someone notices when it
# is unhealthy, and can see why.
#
#   ALB access logs   an S3 bucket the ALB writes every request to
#   uptime checks     Route 53 health checks on public URLs, from outside AWS
#   alarms            site down · node CPU / memory high · node failed ·
#                     WAF blocking a burst — all to one SNS topic
#   dashboard         <project>-<env>: traffic, errors, latency, WAF, nodes,
#                     pods, deploys, alarm states — one page
#
# The ALB itself is the Load Balancer Controller's, so this module cannot
# alarm on its 5xx rate: the ALB's ID is only known once it exists. The
# dashboard finds its metrics by name instead (the cluster project names the
# ALB after the cluster), and the uptime checks catch an outage.

locals {
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
  name_prefix = "${var.project_name}-${var.environment}"
  region      = data.aws_region.current.name
  account_id  = data.aws_caller_identity.current.account_id

  alarm_actions = var.alarm_topic_arn == null ? [] : [var.alarm_topic_arn]
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─── ALB access logs ─────────────────────────────────────────────────────────
# One object per few minutes per ALB node: client IP, request, status, target,
# timings. ALB can only write to SSE-S3 buckets, not KMS. force_destroy: these
# are disposable, and a non-empty bucket would otherwise block `make down`.

data "aws_elb_service_account" "this" {}

resource "aws_s3_bucket" "alb_logs" {
  count = var.alb_access_logs ? 1 : 0

  bucket        = "${local.name_prefix}-alb-logs-${local.account_id}"
  force_destroy = true

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-logs" })
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  count = var.alb_access_logs ? 1 : 0

  bucket                  = aws_s3_bucket.alb_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  count = var.alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  count = var.alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id
  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration {
      days = var.log_retention_days
    }
  }
}

# The ELB service writes as its regional account (older regions) or as the
# log delivery service (newer ones) — both are allowed, only into this
# account's prefix.
resource "aws_s3_bucket_policy" "alb_logs" {
  count = var.alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ElbAccountWrites"
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.this.arn }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs[0].arn}/${var.alb_log_prefix}/AWSLogs/${local.account_id}/*"
      },
      {
        Sid       = "LogDeliveryWrites"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs[0].arn}/${var.alb_log_prefix}/AWSLogs/${local.account_id}/*"
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.alb_logs[0].arn, "${aws_s3_bucket.alb_logs[0].arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}

# ─── Uptime checks ───────────────────────────────────────────────────────────
# Route 53 checkers in several regions request each URL every 30 seconds over
# HTTPS; three failures in a row mark it unhealthy. This is the view of a user
# on the internet — DNS, TLS, WAF, ALB and the pods all have to work.
#
# Route 53 publishes health check metrics in us-east-1 only, so the alarms
# below must be created there.

resource "aws_route53_health_check" "this" {
  for_each = var.uptime_checks

  type              = "HTTPS"
  fqdn              = each.value.fqdn
  port              = 443
  resource_path     = each.value.path
  request_interval  = 30
  failure_threshold = 3
  enable_sni        = true

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-${each.key}" })
}

resource "aws_cloudwatch_metric_alarm" "uptime" {
  for_each = var.uptime_checks

  alarm_name        = "${local.name_prefix}-down-${each.key}"
  alarm_description = "https://${each.value.fqdn}${each.value.path} is failing its Route 53 health check — the site is down for users."

  namespace   = "AWS/Route53"
  metric_name = "HealthCheckStatus"
  dimensions  = { HealthCheckId = aws_route53_health_check.this[each.key].id }
  statistic   = "Minimum"
  period      = 60

  comparison_operator = "LessThanThreshold"
  threshold           = 1
  evaluation_periods  = 2
  treat_missing_data  = "breaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = local.region == "us-east-1"
      error_message = "Route 53 health check metrics exist only in us-east-1; create uptime alarms there."
    }
  }
}

# ─── Node alarms (Container Insights) ────────────────────────────────────────
# Cluster-wide averages, so one busy node does not page anyone; a whole
# cluster running hot for ten minutes does. Needs Container Insights, which
# publishes these.

resource "aws_cloudwatch_metric_alarm" "node_cpu" {
  count = var.container_insights_enabled ? 1 : 0

  alarm_name        = "${local.name_prefix}-node-cpu-high"
  alarm_description = "Average node CPU in ${var.cluster_name} above ${var.cpu_alarm_threshold}% for 10 minutes — the Cluster Autoscaler may be at node_max_size."

  namespace   = "ContainerInsights"
  metric_name = "node_cpu_utilization"
  dimensions  = { ClusterName = var.cluster_name }
  statistic   = "Average"
  period      = 300

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cpu_alarm_threshold
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "node_memory" {
  count = var.container_insights_enabled ? 1 : 0

  alarm_name        = "${local.name_prefix}-node-memory-high"
  alarm_description = "Average node memory in ${var.cluster_name} above ${var.memory_alarm_threshold}% for 10 minutes."

  namespace   = "ContainerInsights"
  metric_name = "node_memory_utilization"
  dimensions  = { ClusterName = var.cluster_name }
  statistic   = "Average"
  period      = 300

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.memory_alarm_threshold
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "node_failed" {
  count = var.container_insights_enabled ? 1 : 0

  alarm_name        = "${local.name_prefix}-node-failed"
  alarm_description = "A node in ${var.cluster_name} is not Ready."

  namespace   = "ContainerInsights"
  metric_name = "cluster_failed_node_count"
  dimensions  = { ClusterName = var.cluster_name }
  statistic   = "Maximum"
  period      = 300

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = local.common_tags
}

# ─── WAF alarm ───────────────────────────────────────────────────────────────
# A burst of blocked requests is someone probing the site. The WAF already
# stops them; this makes sure a person knows.

resource "aws_cloudwatch_metric_alarm" "waf_blocked" {
  count = var.waf_enabled ? 1 : 0

  alarm_name        = "${local.name_prefix}-waf-blocking"
  alarm_description = "WAF ${var.waf_web_acl_name} blocked more than ${var.waf_blocked_threshold} requests in 5 minutes. Which rule and which IPs: the aws-waf-logs-${var.waf_web_acl_name} log group."

  namespace   = "AWS/WAFV2"
  metric_name = "BlockedRequests"
  dimensions  = { WebACL = var.waf_web_acl_name, Region = local.region, Rule = "ALL" }
  statistic   = "Sum"
  period      = 300

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.waf_blocked_threshold
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = local.common_tags
}

# ─── Dashboard ───────────────────────────────────────────────────────────────
# CloudWatch → Dashboards → <project>-<env>. The ALB graphs SEARCH for the
# load balancer named after the cluster, so they fill in once the cluster
# project has created it, and survive it being recreated.

locals {
  alb_search = "{AWS/ApplicationELB,LoadBalancer} \"${var.alb_name}\""

  alarm_arns = concat(
    [for a in aws_cloudwatch_metric_alarm.uptime : a.arn],
    aws_cloudwatch_metric_alarm.node_cpu[*].arn,
    aws_cloudwatch_metric_alarm.node_memory[*].arn,
    aws_cloudwatch_metric_alarm.node_failed[*].arn,
    aws_cloudwatch_metric_alarm.waf_blocked[*].arn,
    var.extra_alarm_arns,
  )

  widgets = concat(
    [
      {
        type = "text", x = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "## ${local.name_prefix}\nCluster **${var.cluster_name}** · ALB **${var.alb_name}** · alarms go to SNS · logs: `/aws/containerinsights/${var.cluster_name}/application`, `/aws/eks/${var.cluster_name}/cluster`${var.waf_enabled ? ", `aws-waf-logs-${var.waf_web_acl_name}`" : ""}"
        }
      },
    ],
    # CloudWatch refuses an alarm widget with no alarms in it.
    [for w in [
      {
        type       = "alarm", x = 0, y = 2, width = 24, height = 3
        properties = { title = "Alarms", alarms = local.alarm_arns }
      },
    ] : w if length(local.alarm_arns) > 0],
    [
      {
        type = "metric", x = 0, y = 5, width = 8, height = 6
        properties = {
          title   = "Requests / min", region = local.region, view = "timeSeries", stat = "Sum", period = 60
          metrics = [[{ expression = "SEARCH('${local.alb_search} MetricName=\"RequestCount\"', 'Sum', 60)", id = "requests", label = "requests" }]]
        }
      },
      {
        type = "metric", x = 8, y = 5, width = 8, height = 6
        properties = {
          title = "5xx errors / min", region = local.region, view = "timeSeries", stat = "Sum", period = 60
          metrics = [
            [{ expression = "SEARCH('${local.alb_search} MetricName=\"HTTPCode_Target_5XX_Count\"', 'Sum', 60)", id = "app5xx", label = "from the app" }],
            [{ expression = "SEARCH('${local.alb_search} MetricName=\"HTTPCode_ELB_5XX_Count\"', 'Sum', 60)", id = "alb5xx", label = "from the ALB" }],
          ]
        }
      },
      {
        type = "metric", x = 16, y = 5, width = 8, height = 6
        properties = {
          title   = "Response time p95 (s)", region = local.region, view = "timeSeries", period = 60
          metrics = [[{ expression = "SEARCH('${local.alb_search} MetricName=\"TargetResponseTime\"', 'p95', 60)", id = "p95", label = "p95" }]]
        }
      },
    ],
    [for w in [
      {
        type = "metric", x = 0, y = 11, width = 12, height = 6
        properties = {
          title = "WAF: allowed vs blocked", region = local.region, view = "timeSeries", stat = "Sum", period = 300
          metrics = [
            ["AWS/WAFV2", "AllowedRequests", "WebACL", var.waf_web_acl_name, "Region", local.region, "Rule", "ALL", { label = "allowed" }],
            ["AWS/WAFV2", "BlockedRequests", "WebACL", var.waf_web_acl_name, "Region", local.region, "Rule", "ALL", { label = "blocked" }],
          ]
        }
      },
    ] : w if var.waf_enabled],
    [
      {
        type = "metric", x = 12, y = 11, width = 12, height = 6
        properties = {
          title = "Deploys (all environments)", region = local.region, view = "timeSeries", stat = "Sum", period = 3600
          metrics = [
            ["Deployments", "Successes", { label = "succeeded" }],
            ["Deployments", "Failures", { label = "failed" }],
          ]
        }
      },
    ],
    [for w in [
      {
        type = "metric", x = 0, y = 17, width = 8, height = 6
        properties = {
          title = "Node CPU / memory %", region = local.region, view = "timeSeries", stat = "Average", period = 60
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", var.cluster_name, { label = "CPU" }],
            ["ContainerInsights", "node_memory_utilization", "ClusterName", var.cluster_name, { label = "memory" }],
          ]
        }
      },
      {
        type = "metric", x = 8, y = 17, width = 8, height = 6
        properties = {
          title = "Nodes", region = local.region, view = "timeSeries", stat = "Average", period = 60
          metrics = [
            ["ContainerInsights", "cluster_node_count", "ClusterName", var.cluster_name, { label = "nodes" }],
            ["ContainerInsights", "cluster_failed_node_count", "ClusterName", var.cluster_name, { label = "failed" }],
          ]
        }
      },
      {
        type = "metric", x = 16, y = 17, width = 8, height = 6
        properties = {
          title   = "Pod CPU % by namespace", region = local.region, view = "timeSeries", period = 60
          metrics = [[{ expression = "SEARCH('{ContainerInsights,ClusterName,Namespace} MetricName=\"pod_cpu_utilization\" ClusterName=\"${var.cluster_name}\"', 'Average', 60)", id = "podcpu", label = "" }]]
        }
      },
    ] : w if var.container_insights_enabled],
  )
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = local.name_prefix
  dashboard_body = jsonencode({ widgets = local.widgets })
}
