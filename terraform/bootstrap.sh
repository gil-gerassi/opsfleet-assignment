#!/usr/bin/env bash
#
# Runs the full deploy in one command: terraform init, then the two-stage
# apply the EKS/Karpenter provider setup requires on a clean run (the
# kubernetes/helm/kubectl providers can't configure themselves until the
# EKS cluster already exists — see README.md for why).
#
# Usage:
#   ./bootstrap.sh          # prompts for confirmation on each apply
#   ./bootstrap.sh -y        # passes -auto-approve to both applies (no prompts)

set -euo pipefail

# Always run from this script's own directory, regardless of where it's called from.
cd "$(dirname "${BASH_SOURCE[0]}")"

AUTO_APPROVE=""
if [[ "${1:-}" == "-y" || "${1:-}" == "--auto-approve" ]]; then
  AUTO_APPROVE="-auto-approve"
fi

if ! command -v terraform &> /dev/null; then
  echo "terraform is not installed or not on PATH." >&2
  exit 1
fi

if [[ ! -f terraform.tfvars ]]; then
  echo ">> No terraform.tfvars found, copying from terraform.tfvars.example"
  cp terraform.tfvars.example terraform.tfvars
  echo "   Review terraform.tfvars (region especially) before re-running if needed."
fi

echo ">> terraform init"
terraform init -upgrade

echo ">> Stage 1/2: creating VPC + EKS cluster"
terraform apply -target=module.vpc -target=module.eks $AUTO_APPROVE

echo ">> Stage 2/2: Karpenter (IAM/SQS, Helm release, EC2NodeClass, NodePools)"
terraform apply $AUTO_APPROVE

CLUSTER_NAME=$(terraform output -raw cluster_name)
REGION=$(terraform output -raw region)

echo ""
echo ">> Done. Configuring kubectl..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

echo ""
echo ">> Cluster nodes:"
kubectl get nodes -L kubernetes.io/arch,node-pool
