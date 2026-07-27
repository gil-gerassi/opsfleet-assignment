################################################################################
# IAM roles (controller + node), Pod Identity association, SQS interruption
# queue and EventBridge rules that Karpenter needs.
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  namespace                       = "karpenter"
  create_pod_identity_association = true

  enable_inline_policy = true

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

# One-time, account-wide prerequisite for launching EC2 Spot Instances.
# Without it, Karpenter's spot launches/consolidation fail with
# AuthFailure.ServiceLinkedRoleCreationNotPermitted. Safe to manage here
# since it's a singleton per account - if it already exists (e.g. created
# outside Terraform), import it instead of re-running apply blind.
resource "aws_iam_service_linked_role" "spot" {
  aws_service_name = "spot.amazonaws.com"
}

################################################################################
# Karpenter controller (Helm)
################################################################################

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = "karpenter"
  create_namespace = true

  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version

  wait   = true
  atomic = true

  values = [
    yamlencode({
      serviceAccount = {
        name = "karpenter"
      }
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter.queue_name
      }
      controller = {
        resources = {
          requests = {
            cpu    = "1"
            memory = "1Gi"
          }
          limits = {
            memory = "1Gi"
          }
        }
      }
      # Run the controller on the system node group, never on nodes it
      # provisions itself.
      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
        }
      ]
      nodeSelector = {
        "node-pool" = "system"
      }
    })
  ]

  depends_on = [
    module.eks,
    module.karpenter,
  ]
}
