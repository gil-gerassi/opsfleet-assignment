# EKS + Karpenter (Graviton + Spot) — POC

Terraform for an EKS cluster where [Karpenter](https://karpenter.sh)
autoscales nodes across both **x86_64** and **arm64 (Graviton)**, Spot-first
with On-Demand fallback.

Requires Terraform >= 1.10.0.

## Deploy the cluster

```bash
./bootstrap.sh          # prompts before each apply
./bootstrap.sh -y       # non-interactive
```

Runs `terraform init` + the two-stage `apply` this setup needs, then points
`kubectl` at the new cluster. Takes ~15–20 minutes.

Only needed once, for the initial cluster creation. After that, `terraform
apply` on its own works as usual for any changes.

## Deploy a service on a specific architecture

Karpenter labels every node it launches with `kubernetes.io/arch`. Target one
with a `nodeSelector` — [deployment-x86.yaml](deployment-x86.yaml):

```yaml
spec:
  nodeSelector:
    kubernetes.io/arch: amd64
  containers:
    - name: hello
      image: public.ecr.aws/nginx/nginx:latest
```

and [deployment-arm64.yaml](deployment-arm64.yaml) (same shape, `arch: arm64`):

```yaml
spec:
  nodeSelector:
    kubernetes.io/arch: arm64
  containers:
    - name: hello
      image: public.ecr.aws/nginx/nginx:latest
```

```bash
kubectl apply -f deployment-x86.yaml     # lands on the amd64 NodePool
kubectl apply -f deployment-arm64.yaml   # lands on the arm64 (Graviton) NodePool

kubectl get nodes -L kubernetes.io/arch   # watch Karpenter launch a node for each
```

`nodeSelector` only controls *placement* — the image still needs to support
the target arch, or the pod schedules fine and then crashes with
`exec format error`. Build multi-arch images with
`docker buildx build --platform linux/amd64,linux/arm64 ...`.

## Cleaning up

Karpenter's EC2 instances aren't in Terraform state — remove the workloads
and NodePools first so Karpenter deprovisions them, then destroy:

```bash
kubectl delete -f deployment-x86.yaml -f deployment-arm64.yaml
kubectl delete nodepool amd64 arm64
terraform destroy
```
