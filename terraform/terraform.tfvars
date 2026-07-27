# Copy this file to terraform.tfvars and adjust as needed.

region             = "eu-central-1"
cluster_name       = "opsfleet-startup-eks-poc"
kubernetes_version = "1.35"
vpc_cidr           = "10.0.0.0/16"
single_nat_gateway = true
karpenter_version  = "1.11.3"
allowed_ingress_cidr = "0.0.0.0/0" # Replace with your own public IP address for security


tags = {
  Owner = "platform-team"
}
