module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access = true

  # Maps the identity running `terraform apply` in as a cluster admin via an
  # EKS access entry, so kubectl/helm/kubectl-provider calls work immediately.
  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns = {
      configuration_values = jsonencode({
        # Allow CoreDNS to schedule on the system node group's tainted-free
        # nodes even before Karpenter is up - keeps cluster bootstrap smooth.
        tolerations = [
          {
            key      = "CriticalAddonsOnly"
            operator = "Exists"
          }
        ]
      })
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
  }

  # A small, statically-managed node group exists only to run cluster-critical
  # add-ons and the Karpenter controller itself - Karpenter can't provision
  # nodes for a cluster that has nowhere to run Karpenter. Every application
  # workload after this point runs on Karpenter-provisioned nodes instead.
  # It runs on Graviton on-demand instances since it needs to be small and stable.
  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_ARM_64_STANDARD"
      instance_types = var.system_node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = 1
      max_size     = 3
      desired_size = 2

      labels = {
        "node-pool" = "system"
      }

      taints = {
        critical_addons = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # Tags the shared node security group so Karpenter's EC2NodeClass can find
  # it via securityGroupSelectorTerms instead of a hardcoded SG ID.
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = local.tags
}
