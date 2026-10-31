# terraform

AWS infrastructure for the platform: one VPC and one EKS cluster per
environment (`dev`, `uat`, `prod`), plus a shared ECR registry. Kubernetes
workloads, controllers and Helm live in `../cluster`.

Design, the handover contract and the Kubespray evaluation: [docs/eks.md](docs/eks.md).

## Needs

Terraform >= 1.10, the AWS CLI, `kubectl`, and credentials for account
`570417737010`.

## First time (once per account)

```bash
make bootstrap                 # S3 state bucket                          ~1 min
make migrate-state             # move any local states into it — or `make init` on a fresh machine
make global-init
make global-plan               # ECR: imports the existing repositories
make global-apply
```

## An environment

```bash
make myip         WORKSPACE=dev    # is your IP allowed to reach the Kubernetes API?
make plan         WORKSPACE=dev
make apply-plan   WORKSPACE=dev    # ~20 min — EKS control plane, nodes, add-ons
make kubeconfig   WORKSPACE=dev    # kubectl context, then lists the nodes
make output       WORKSPACE=dev
```

`make cost WORKSPACE=<env>` prints what it bills while running — dev is
~$8/day. Tear it down when you are not using it:

```bash
make -C ../cluster cluster-down WORKSPACE=dev   # Ingress ALBs and PVC volumes first
make destroy WORKSPACE=dev
```

`make help` lists every target.
