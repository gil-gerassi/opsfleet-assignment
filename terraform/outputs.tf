output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "region" {
  description = "AWS region the cluster was deployed into."
  value       = var.region
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  description = "ID of the dedicated VPC."
  value       = module.vpc.vpc_id
}

output "karpenter_node_iam_role_name" {
  description = "IAM role name used for Karpenter-provisioned nodes (referenced by EC2NodeClass)."
  value       = module.karpenter.node_iam_role_name
}

output "ingress_hostname" {
  description = "ALB hostname for the hello services. Provisioning takes a few minutes after apply - if empty, run `kubectl get ingress hello` to check."
  value       = try(kubernetes_ingress_v1.hello.status[0].load_balancer[0].ingress[0].hostname, null)
}

output "nodepools" {
  description = "Karpenter NodePools created and how to target them."
  value = {
    amd64 = "kubectl.kubernetes.io - nodeSelector: { kubernetes.io/arch: amd64 }"
    arm64 = "kubectl.kubernetes.io - nodeSelector: { kubernetes.io/arch: arm64 }"
  }
}
