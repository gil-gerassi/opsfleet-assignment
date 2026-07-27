variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster (also used to derive VPC/Karpenter discovery tags)."
  type        = string
  default     = "opsfleet-startup-eks-poc"
}

variable "kubernetes_version" {
  description = "EKS control plane Kubernetes version. Check https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html for the current latest."
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "CIDR block for the dedicated VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT Gateway instead of one per AZ. Cheaper, less resilient - fine for a POC."
  type        = bool
  default     = true
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version (aws/karpenter-provider-aws release). Check https://github.com/aws/karpenter-provider-aws/releases for the current latest."
  type        = string
  default     = "1.11.3"
}

variable "system_node_instance_types" {
  description = "Instance type(s) for the small managed node group that bootstraps core add-ons and the Karpenter controller itself, before Karpenter can provision anything. Defaults to a Graviton (arm64) burstable instance."
  type        = list(string)
  default     = ["t4g.medium"]
}

variable "alb_controller_version" {
  description = "AWS Load Balancer Controller Helm chart version (aws/eks-charts release). Check https://github.com/aws/eks-charts/releases for the current latest."
  type        = string
  default     = "3.4.2"
}

variable "allowed_ingress_cidr" {
  description = "CIDR allowed to reach the ALB (inbound-cidrs on the Ingress). Restrict to your own public IP/32."
  type        = string
  default     = "0.0.0.0/0"
}

variable "tags" {
  description = "Extra tags applied to all resources."
  type        = map(string)
  default     = {}
}
