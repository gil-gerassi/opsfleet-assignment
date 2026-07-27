################################################################################
# Services fronting the hello-arm64 / hello-x86 Deployments (applied
# separately via deployment-arm64.yaml / deployment-x86.yaml). Selectors
# match on label only, so these work regardless of how the Deployments
# were created.
################################################################################

resource "kubernetes_service_v1" "hello_arm64" {
  metadata {
    name = "hello-arm64"
  }

  spec {
    selector = {
      app = "hello-arm64"
    }

    port {
      port        = 80
      target_port = 80
    }
  }
}

resource "kubernetes_service_v1" "hello_x86" {
  metadata {
    name = "hello-x86"
  }

  spec {
    selector = {
      app = "hello-x86"
    }

    port {
      port        = 80
      target_port = 80
    }
  }
}

################################################################################
# Ingress (ALB) - single internet-facing ALB, single root path, weighted
# 50/50 across both arm64 and x86 target groups so one URL demonstrates
# Karpenter scheduling the same workload across both architectures. Locked
# down to a single inbound CIDR via the ALB's auto-managed security group.
################################################################################

resource "kubernetes_ingress_v1" "hello" {
  metadata {
    name = "hello"
    annotations = {
      "alb.ingress.kubernetes.io/scheme"        = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"   = "ip"
      "alb.ingress.kubernetes.io/listen-ports"  = jsonencode([{ HTTP = 80 }])
      "alb.ingress.kubernetes.io/inbound-cidrs" = var.allowed_ingress_cidr

      # Custom action referenced below via serviceName "weighted-routing" /
      # servicePort "use-annotation" - the only way to fan one path out to
      # multiple target groups, since a plain Ingress rule allows only one
      # backend.
      "alb.ingress.kubernetes.io/actions.weighted-routing" = jsonencode({
        type = "forward"
        forwardConfig = {
          targetGroups = [
            {
              serviceName = kubernetes_service_v1.hello_arm64.metadata[0].name
              servicePort = "80"
              weight      = 50
            },
            {
              serviceName = kubernetes_service_v1.hello_x86.metadata[0].name
              servicePort = "80"
              weight      = 50
            },
          ]
        }
      })
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "weighted-routing"
              port {
                name = "use-annotation"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}
