provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# Used to mint a short-lived auth token for the kubernetes/helm/kubectl
# providers so they can talk to the cluster right after it's created,
# without needing a pre-existing kubeconfig.
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# Used only to apply Karpenter's NodePool / EC2NodeClass custom resources,
# since those CRDs don't exist until the Karpenter helm release is installed
# and the kubernetes_manifest resource struggles with CRDs that appear mid-apply.
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
  apply_retry_count      = 15
}
