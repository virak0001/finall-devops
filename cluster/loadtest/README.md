# Scaling demo

## Before

```bash
cd ~/Desktop/aws-devops/dev-finall
make up WORKSPACE=dev
export KUBECONFIG=~/.kube/config-dev
kubectl get nodes
kubectl get hpa -A
```

## Pod scaling (HPA)

Terminal 1

```bash
export KUBECONFIG=~/.kube/config-dev
kubectl get hpa -A -w
```

Terminal 2

```bash
export KUBECONFIG=~/.kube/config-dev
kubectl get pods -n web-service -w
```

Terminal 3

```bash
cd ~/Desktop/aws-devops/dev-finall/cluster
make load-test WORKSPACE=dev VUS=100 HOLD=5m
make load-test WORKSPACE=uat VUS=100 HOLD=5m
make load-test WORKSPACE=prod VUS=100 HOLD=5m
```

```bash
make load-test WORKSPACE=dev VUS=200 HOLD=5m
```

## Node scaling (Cluster Autoscaler)

Terminal 1

```bash
export KUBECONFIG=~/.kube/config-dev
export KUBECONFIG=~/.kube/config-uat
export KUBECONFIG=~/.kube/config-prod
kubectl get nodes -w
```

Terminal 2

```bash
cd ~/Desktop/aws-devops/dev-finall/cluster
export KUBECONFIG=~/.kube/config-dev
make node-scale-test WORKSPACE=dev
kubectl get pods -l app=scale-test -w

cd ~/Desktop/aws-devops/dev-finall/cluster
export KUBECONFIG=~/.kube/config-uat
make node-scale-test WORKSPACE=uat
kubectl get pods -l app=scale-test -w

export KUBECONFIG=~/.kube/config-prod
make node-scale-test WORKSPACE=prod
kubectl get pods -l app=scale-test -w
```

Terminal 3

```bash
export KUBECONFIG=~/.kube/config-dev
kubectl -n kube-system logs deploy/cluster-autoscaler -f | grep -E 'scale-up|scale-down'

export KUBECONFIG=~/.kube/config-uat
kubectl -n kube-system logs deploy/cluster-autoscaler -f | grep -E 'scale-up|scale-down'

export KUBECONFIG=~/.kube/config-prod
kubectl -n kube-system logs deploy/cluster-autoscaler -f | grep -E 'scale-up|scale-down'
```

Clean

```bash
cd ~/Desktop/aws-devops/dev-finall/cluster
make node-scale-clean WORKSPACE=dev
make node-scale-clean WORKSPACE=uat
make node-scale-clean WORKSPACE=prod
```

## Terraform limits

```bash
cd ~/Desktop/aws-devops/dev-finall/terraform
grep -n 'node_' env/dev.tfvars
make plan WORKSPACE=dev
```

## After

```bash
cd ~/Desktop/aws-devops/dev-finall
make down WORKSPACE=dev
```
