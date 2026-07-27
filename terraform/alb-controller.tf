################################################################################
# AWS Load Balancer Controller - IAM (Pod Identity)
################################################################################

data "aws_iam_policy_document" "aws_load_balancer_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "aws_load_balancer_controller" {
  name               = "${var.cluster_name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume.json

  tags = local.tags
}

# Official policy from kubernetes-sigs/aws-load-balancer-controller
# (docs/install/iam_policy.json).
resource "aws_iam_role_policy" "aws_load_balancer_controller" {
  name   = "aws-load-balancer-controller"
  role   = aws_iam_role.aws_load_balancer_controller.id
  policy = file("${path.module}/policies/aws-load-balancer-controller-iam-policy.json")
}

resource "aws_eks_pod_identity_association" "aws_load_balancer_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.aws_load_balancer_controller.arn
}

################################################################################
# AWS Load Balancer Controller (Helm)
################################################################################

resource "helm_release" "aws_load_balancer_controller" {
  name      = "aws-load-balancer-controller"
  namespace = "kube-system"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.alb_controller_version

  wait   = true
  atomic = true

  values = [
    yamlencode({
      clusterName = module.eks.cluster_name
      region      = var.region
      vpcId       = module.vpc.vpc_id

      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
      }

      # Runs on the system node group, same as Karpenter's own controller -
      # it needs to be up before Karpenter can provision workload nodes for
      # anything it manages Ingress/Service objects for.
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
    aws_eks_pod_identity_association.aws_load_balancer_controller,
  ]
}
