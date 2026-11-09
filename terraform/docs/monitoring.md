# Monitoring, logging and auditing

Three questions, three places to look:

| Question | Built by | Where to look |
|---|---|---|
| **Is it healthy?** (monitoring) | `modules/monitoring`, one per environment | CloudWatch → **Dashboards** → `upskill-devops-<env>`, and **Alarms** |
| **What happened?** (logging) | Container Insights (`modules/eks`), `modules/waf`, `modules/monitoring` | CloudWatch → **Logs Insights**; S3 for ALB access logs |
| **Who did what?** (auditing) | `modules/audit`, once per account (`global/`) | CloudTrail → **Event history**; Logs Insights on `/upskill-devops/cloudtrail` |

Every alarm — deployments, security, and each environment's — notifies one SNS
topic, `upskill-devops-alerts`, so one email subscription covers everything.

## Turning it on

```bash
cd ~/Desktop/aws-devops/dev-finall/terraform
echo 'alert_email = "you@example.com"' > global/terraform.tfvars
make global-plan
make global-apply
```

AWS emails a confirmation link to that address. **Nothing is delivered until it
is clicked.** `global/` is applied once; it holds the audit trail and the alerts
topic, and survives `make down`.

Each environment's monitoring comes up with the environment:

```bash
cd ~/Desktop/aws-devops/dev-finall
make up WORKSPACE=dev
```

## What exists

### Monitoring — per environment

| | What it watches | Alarm when |
|---|---|---|
| Uptime: `site` | `https://<env host>/` from Route 53 checkers on the internet | 3 failures in a row (≈1.5 min) |
| Uptime: `auth-api` | `https://<env host>/api/auth/health` | same |
| `node-cpu-high` | average node CPU (Container Insights) | > 80% for 10 min |
| `node-memory-high` | average node memory | > 80% for 10 min |
| `node-failed` | nodes not Ready | ≥ 1 |
| `waf-blocking` | requests the WAF blocked | > 100 in 5 min |
| `deployment-failed` (global) | any failed build, deploy, promotion or rollback | ≥ 1 |

The dashboard: requests, 5xx (from the app and from the ALB), p95 response
time, WAF allowed vs blocked, node CPU/memory, node count, pod CPU by
namespace, deploys, and every alarm's state.

There is no 5xx-*rate* alarm: the ALB belongs to the Load Balancer Controller,
and its ID is unknown to Terraform. The dashboard shows 5xx; the uptime checks
catch an outage.

### Logging

| Log | Where | Kept |
|---|---|---|
| Every container's stdout/stderr | `/aws/containerinsights/<cluster>/application` | `log_retention_days` (dev 7, uat 14, prod 30) |
| Kubelet / containerd / node system | `/aws/containerinsights/<cluster>/dataplane`, `/host` | same |
| EKS control plane: API, **audit**, authenticator | `/aws/eks/<cluster>/cluster` | same |
| Every request the WAF saw, and which rule matched | `aws-waf-logs-upskill-devops-<env>-alb` (Authorization and Cookie redacted) | 30 days |
| Every request the ALB served | `s3://upskill-devops-<env>-alb-logs-<account>/alb/` | `log_retention_days` |
| Every deploy, promotion, rollback, failed build | `/upskill-devops/deployments` | 1 year |
| Network flows | VPC Flow Logs — prod only (`enable_flow_logs`) | — |

### Auditing — whole account

| | |
|---|---|
| CloudTrail trail `upskill-devops-audit` | every management API call, every region → S3 for 1 year (with digest files: `aws cloudtrail validate-logs` proves nothing was edited) and CloudWatch for 90 days |
| `security-root-account-used` | the root user did anything |
| `security-console-login-failed` | ≥ 3 failed console sign-ins in 5 min |
| `security-console-login-without-mfa` | an IAM user signed in without MFA |
| `security-iam-policy-changed` | any IAM policy created, changed, attached, detached |
| `security-api-calls-denied` | ≥ 10 AccessDenied / Unauthorized in 5 min |
| `security-cloudtrail-changed` | a trail created, changed, stopped or deleted |
| Kubernetes audit | `audit` in the EKS control-plane log group |
| Deploy trail | cluster repo commits carry `Initiated-By`, `Source-Commit`, `Jenkins-Build` |

Security alarms email when they **enter** ALARM only — one email per incident.

`root-account-used` will fire while the team works as root. That is the point:
give each member an IAM identity, and this alarm then means something.

## Logs Insights queries

CloudWatch → Logs Insights → pick the log group → paste.

**App errors** — `/aws/containerinsights/upskill-devops-dev/application`

```
fields @timestamp, kubernetes.namespace_name, kubernetes.pod_name, log
| filter log like /(?i)(error|exception|fatal)/
| sort @timestamp desc
| limit 50
```

**What the WAF blocked, and from where** — `aws-waf-logs-upskill-devops-dev-alb`

```
fields @timestamp, httpRequest.clientIp, httpRequest.uri, terminatingRuleId
| filter action = "BLOCK"
| stats count() as blocked by terminatingRuleId, httpRequest.clientIp
| sort blocked desc
```

**Who changed what in AWS** — `/upskill-devops/cloudtrail`

```
fields @timestamp, userIdentity.arn, eventName, eventSource, sourceIPAddress, errorCode
| filter eventName not like /^(Get|List|Describe|Head)/
| sort @timestamp desc
| limit 100
```

**Who changed what in Kubernetes** — `/aws/eks/upskill-devops-dev/cluster`

```
fields @timestamp, user.username, verb, objectRef.resource, objectRef.namespace, objectRef.name
| filter @logStream like /kube-apiserver-audit/
| filter verb in ["create", "update", "patch", "delete"]
| sort @timestamp desc
| limit 100
```

**Deploys** — `/upskill-devops/deployments`

```
fields @timestamp, environment, service, tag, status, initiator
| sort @timestamp desc
```

## Demo

```bash
curl -s -o /dev/null -w '%{http_code}\n' "https://dev.devops-selft-learning.xyz/?id=1%20OR%201=1"
```

403 — then the WAF query above shows the rule and your IP.

```bash
aws cloudwatch set-alarm-state --alarm-name upskill-devops-dev-node-cpu-high \
  --state-value ALARM --state-reason "demo"
```

An email arrives; the dashboard's alarm row turns red; the next evaluation
puts it back to OK.

```bash
aws cloudtrail lookup-events --max-results 5 \
  --lookup-attributes AttributeKey=EventName,AttributeValue=SetAlarmState \
  --query 'Events[].[EventTime,Username,EventName]' --output table
```

The audit trail recorded who just did that.

## Turning pieces off

| Variable (`terraform/env/<env>.tfvars`) | Off removes |
|---|---|
| `enable_monitoring = false` | dashboard, alarms, uptime checks, ALB log bucket |
| `alb_access_logs = false` | only the ALB log bucket (and the Ingress annotation) |
| `enable_container_insights = false` | pod/node logs and metrics, and the node alarms |
| `waf_enabled = false` | the WAF, its logs and its alarm |
| `cpu_alarm_threshold`, `memory_alarm_threshold` | (thresholds, default 80) |

`global/`: `enable_audit = false` removes the trail and security alarms; the
trail bucket is kept (`force_destroy = false`) — delete it by hand if meant.

## Cost (approximate, only while it exists)

| | per month |
|---|---|
| Container Insights, 2 nodes | ~$5–8 |
| Uptime checks (2, HTTPS) | ~$2 |
| Dashboard | $3 (first 3 in the account free) |
| Alarms | $0.10 each |
| WAF logs, ALB logs | cents at demo traffic |
| CloudTrail | first trail free; CloudWatch copy ~$0.50/GB |
