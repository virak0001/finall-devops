# EKS platform — design and contract

## Layout

Three Terraform roots, one state each (or one per workspace):

| Root         | What                                                     | State                                  | Applied             |
| ------------ | -------------------------------------------------------- | -------------------------------------- | ------------------- |
| `bootstrap/` | S3 bucket holding every other state                      | local, `bootstrap/terraform.tfstate`   | once per account    |
| `global/`    | ECR, one repository per service; CI push policy          | `global/terraform.tfstate`             | when services change |
| `.`          | VPC + EKS for one environment                            | `env:/<ws>/environments/terraform.tfstate` | per environment  |

ECR is shared because a release is a promotion: the image dev ran is the
exact image uat accepts and prod runs. Tags are immutable, so `v1.4.2` can
only ever be one digest.

## What one environment gets

```
                    ┌──────────────── VPC (one per environment) ─────────────────┐
internet ── IGW ─── │ public subnets   ALB (created by the LB controller), NAT    │
                    │ private subnets  EKS control-plane ENIs · nodes · pods     │
                    └─────────────────────────────────────────────────────────────┘
EKS (AWS-managed control plane, 3 AZs)
  ├─ managed node group "default", AL2023, encrypted gp3, IMDSv2
  ├─ add-ons: vpc-cni (NetworkPolicy on) · kube-proxy · coredns · eks-pod-identity-agent
  │           aws-ebs-csi-driver · metrics-server · amazon-cloudwatch-observability (prod)
  ├─ Secrets envelope-encrypted with a KMS key
  ├─ api / audit / authenticator logs → /aws/eks/<cluster>/cluster
  └─ access entries: creator + admin_principal_arns (cluster-admin), team_access (per namespace)
ACM certificate for <site_hostname> and *.<site_hostname>, DNS-validated
SSM parameters /platform/<ws>/* — the handover below
```

| | dev | uat | prod |
| --- | --- | --- | --- |
| AZs | 2 | 2 | 3 |
| NAT gateways | 1 shared | one per AZ | one per AZ |
| nodes (min/desired/max) | 1/2/4 c7i-flex.large | 2/2/4 t3.large | 3/3/6 t3.large |
| hostname | dev.devops-selft-learning.xyz | uat.devops-selft-learning.xyz | devops-selft-learning.xyz, www |
| Container Insights | off | off | on |
| flow logs | off | off | on |
| log retention | 7 d | 14 d | 90 d |
| ~cost while running | $250/mo | $290/mo | $420/mo |

## The contract with `../cluster`

Three things cross the boundary. Nothing else — no state, no Terraform, no
checkout of this repo.

**1. Platform facts, in SSM** at `/platform/<ws>/<key>`. The cluster project
reads them through `scripts/platform.sh` with `PLATFORM_SSM_PREFIX=/platform`.

| key | used for |
| --- | --- |
| `region`, `cluster_name` | `aws eks update-kubeconfig` |
| `vpc_id` | load balancer controller `--set vpcId` |
| `lbc_role_arn` | reference only — the association already binds it |
| `ecr_registry_url`, `ecr_image_prefix` | Helm `global.imageRegistry` |
| `site_url`, `site_hostname` | Ingress `host:` |
| `certificate_arn` | `alb.ingress.kubernetes.io/certificate-arn` (optional — the controller also finds it by host) |
| `route53_zone_id` | external-dns `--zone-id-filter` |
| `public_subnet_cidrs` | team NetworkPolicies admit the ALB from these |
| `secrets_name_prefix`, `secrets_role_prefix` | each team's SecretStore: secret `<prefix>/<team>`, role `<role_prefix><team>` |

**2. Pod identities** — install each controller under exactly this namespace
and service account, with no credentials. Any other name runs with no AWS
permissions.

| namespace / service account | role grants |
| --- | --- |
| `kube-system/aws-load-balancer-controller` | the controller's own v3.5.0 policy — install chart 3.5.0 |
| `kube-system/cluster-autoscaler` | resize Auto Scaling groups tagged `k8s.io/cluster-autoscaler/<cluster>=owned` only |
| `external-dns/external-dns` | records in the one hosted zone |
| `external-secrets/external-secrets` | assume `<cluster>-secrets-*` — nothing else |
| `kube-system/ebs-csi-controller-sa` | EBS volumes (bound by the add-on) |
| `amazon-cloudwatch/cloudwatch-agent` | CloudWatch metrics and logs (bound by the add-on) |

**3. Team secrets** (`secrets.tf`) — per team in `var.teams`: a Secrets
Manager secret `<project>/<ws>/<team>` with no value (the cluster project's
`make secret-push` writes it), and a role `<cluster>-secrets-<team>` that can
read that one secret and is assumable only by the External Secrets role.
The team names must match the cluster project's `helm/values/<team>/`.

Images need no pull secret: nodes pull with their own role
(`AmazonEC2ContainerRegistryPullOnly`), so `ecr-auth` and its CronJob are not
needed on EKS.

## Why EKS and not Kubespray

Kubespray was the first implementation and is kept in git history. On AWS it
cost more effort than it saved:

- **No cloud controller.** Kubespray v2.31.0 cannot install the AWS CCM
  (`external_cloud_provider` rejects `aws`), so `Service type=LoadBalancer`
  stays Pending and the ALB had to be hand-built in Terraform around a fixed
  NodePort. Its bundled EBS CSI image is abandoned on Docker Hub.
- **We ran the control plane.** etcd quorum sizing, a dedicated etcd disk, a
  bastion, an SSH tunnel to the apiserver, and 20-40 minutes of playbook per
  build. EKS runs all of that across three AZs for $0.10/hour.
- **No node elasticity.** Kubespray needs stable addresses, so nodes were
  fixed instances; Cluster Autoscaler or Karpenter had nothing to scale.

What Kubespray would still be right for: on-premises or bare metal, or where
the control plane itself must be customised.

## Gotchas

- **`kubectl` hangs instead of failing** when your IP is not in
  `api_allowed_cidrs`. `make myip` first.
- **Destroy the cluster's own AWS objects first.** The ALB from an Ingress and
  EBS volumes from PVCs are not in Terraform state. Left behind, they keep
  billing and the ALB blocks both the VPC and the certificate from deleting.
  `make -C ../cluster cluster-down` before `make destroy`.
- **Version upgrades go one minor at a time** and cannot be rolled back after
  7 days. The upgrade policy is STANDARD: a version reaching end of standard
  support is auto-upgraded rather than billed at the $0.60/hour extended rate.
- **Add-ons float to EKS's default version** for the cluster's Kubernetes
  version. Add `addon_version` in `modules/eks/addons.tf` to pin one.
- **The LB controller policy is pinned to v3.5.0**
  (`modules/eks/policies/`). A newer controller may call APIs this policy
  predates — update the file from the controller's tag when upgrading.
- **IMDS hop limit is 2** so the CloudWatch agent and Fluent Bit can read
  instance metadata. Any pod can therefore reach the node role; it is kept to
  join, network and pull for that reason.
- **The secrets KMS key cannot be removed from a cluster**, and `destroy`
  schedules it for deletion with a 7-day window.
- **ingress-nginx is not used.** It was retired upstream in March 2026; the
  ALB routes to pods directly through the load balancer controller.
