# Multi-Team DevOps Platform on AWS

## One command

```bash
cd ~/Desktop/aws-devops/dev-finall
make check WORKSPACE=prod
make up WORKSPACE=prod
make up WORKSPACE=uat
make down WORKSPACE=prod
make down WORKSPACE=uat
```

## Check

```bash
cd ~/Desktop/aws-devops/dev-finall/terraform
aws sts get-caller-identity --query Account --output text
make myip WORKSPACE=dev
make myip-set WORKSPACE=dev
```

## Up

```bash
cd ~/Desktop/aws-devops/dev-finall/terraform
make plan WORKSPACE=dev
make apply-plan WORKSPACE=dev
```

```bash
cd ~/Desktop/aws-devops/dev-finall/cluster
make platform-pull WORKSPACE=dev
make kubeconfig WORKSPACE=dev
export KUBECONFIG=~/.kube/config-dev
make controllers WORKSPACE=dev   # installs the controllers, including External Secrets
make teams WORKSPACE=dev         # creates the namespaces and wiring
make secrets WORKSPACE=dev       # pushes the secret values
make helm-deploy WORKSPACE=dev   # deploys the apps into those namespaces

```

```bash
cd ~/Desktop/aws-devops/dev-finall/cluster
make argocd-install WORKSPACE=dev
make argocd-expose WORKSPACE=dev
make argocd-password WORKSPACE=dev
```

## URLs

```
https://dev.devops-selft-learning.xyz
https://dev.devops-selft-learning.xyz/api/auth/health
https://argocd.dev.devops-selft-learning.xyz
```

## Status

```bash
kubectl get nodes
kubectl get pods -A
kubectl get ingress -A
dig +short @8.8.8.8 dev.devops-selft-learning.xyz
```

## Load test

```bash
cd ~/Desktop/aws-devops/dev-finall/cluster
export KUBECONFIG=~/.kube/config-dev
kubectl get hpa -A -w
make load-test WORKSPACE=dev
make load-test WORKSPACE=dev VUS=100 HOLD=5m
```

```bash
cd ~/Desktop/aws-devops/dev-finall/cluster
export KUBECONFIG=~/.kube/config-dev
kubectl get nodes -w
make node-scale-test WORKSPACE=dev
make node-scale-clean WORKSPACE=dev
```

## Down

```bash
cd ~/Desktop/aws-devops/dev-finall/cluster
make cluster-down WORKSPACE=dev
```

```bash
cd ~/Desktop/aws-devops/dev-finall/terraform
make destroy WORKSPACE=dev
```

## First time in a new account

```bash
cd ~/Desktop/aws-devops/dev-finall/terraform
make bootstrap
make init
make global-init
make global-plan
make global-apply
```


```bash
cd ~/Desktop/aws-devops/dev-finall/cluster
make cluster-down WORKSPACE=prod
# wait 1 minute so external-dns can remove the DNS records

cd ../terraform
make destroy WORKSPACE=prod
make plan WORKSPACE=prod
make apply-plan WORKSPACE=prod

cd ../cluster
make platform-pull WORKSPACE=prod
make kubeconfig WORKSPACE=prod
export KUBECONFIG=~/.kube/config-prod
make controllers WORKSPACE=prod
make teams WORKSPACE=prod
make secrets WORKSPACE=prod
make helm-deploy WORKSPACE=prod

```

```bash
cd ~/Desktop/aws-devops/dev-finall/cluster
cp helm/env/dev.env helm/env/uat.env
chmod 600 helm/env/uat.env
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$(openssl rand -hex 32)|; s|^JWT_REFRESH_SECRET=.*|JWT_REFRESH_SECRET=$(openssl rand -hex 32)|" helm/env/uat.env
```