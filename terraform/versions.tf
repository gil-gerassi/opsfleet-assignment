terraform {
  required_version = ">= 1.10.0" # Leverages modern native ephemeral data protections

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.52.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2" # Completely avoids known v2 identity-state crashes on EKS
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.4" # 3.0 has no stable release yet (betas only as of 2026-07)
    }
  }
}
