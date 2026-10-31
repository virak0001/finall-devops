# Deployment history and the alert on it — shared by every environment.
#
#   Jenkins ──put-log-events──► /upskill-devops/deployments   stream per env
#                                     │  metric filter: status is a failure
#                                     ▼
#                           Deployments/Failures  ──alarm──► SNS ──► email
#
# One JSON event per deploy, promotion, rollback and failed build, written by
# the shared library (recordDeployment): who, which service, which image tag,
# which commits, which environment, and how it ended. The history to query:
#
#   aws logs start-query --log-group-name /upskill-devops/deployments \
#     --start-time $(date -d '-7 days' +%s) --end-time $(date +%s) \
#     --query-string 'fields @timestamp, environment, service, tag, status, initiator | sort @timestamp desc'
#
# Here rather than per environment because Jenkins is shared too, and one
# place to look beats three.

resource "aws_cloudwatch_log_group" "deployments" {
  name = "/${var.project_name}/deployments"

  # A year: long enough to answer "what was prod running in March?".
  retention_in_days = 365
}

# Counts every event whose status is a failure. The value is 1 per event, so
# Sum over a period is "how many deploys failed".
resource "aws_cloudwatch_log_metric_filter" "deployment_failures" {
  name           = "deployment-failures"
  log_group_name = aws_cloudwatch_log_group.deployments.name
  pattern        = "{ ($.status = \"FAILED\") || ($.status = \"ROLLED_BACK\") || ($.status = \"ROLLBACK_FAILED\") || ($.status = \"BUILD_FAILED\") }"

  metric_transformation {
    name          = "Failures"
    namespace     = "Deployments"
    value         = "1"
    default_value = "0"
  }
}

# The same, for successes — the other half of a deploy-frequency graph.
resource "aws_cloudwatch_log_metric_filter" "deployment_successes" {
  name           = "deployment-successes"
  log_group_name = aws_cloudwatch_log_group.deployments.name
  pattern        = "{ $.status = \"SUCCEEDED\" }"

  metric_transformation {
    name          = "Successes"
    namespace     = "Deployments"
    value         = "1"
    default_value = "0"
  }
}

# ─── Alerting ────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

# Email needs confirming: AWS sends a link to the address, and nothing is
# delivered until it is clicked. Null skips the subscription — the alarm still
# fires and shows in the console.
resource "aws_sns_topic_subscription" "alerts_email" {
  count = var.alert_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "deployment_failed" {
  alarm_name        = "${var.project_name}-deployment-failed"
  alarm_description = "A pipeline build, deploy, promotion or rollback failed. Details: the /${var.project_name}/deployments log group, or the Jenkins build linked in the event."

  namespace   = "Deployments"
  metric_name = "Failures"
  statistic   = "Sum"
  period      = 300

  # Any failure in a five-minute window. A failed deploy is always worth a look.
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 1

  # No events at all is the normal state between deploys, not a fault.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
