terraform {
  # The management-cluster-k8s child module requires >= 1.11.0 for write-only attributes
  required_version = ">= 1.11.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 7.0.0, < 9.0.0"
    }
    # 3.3.0 introduced the numeric attribute of the random_string resource
    random = {
      source  = "hashicorp/random"
      version = "~> 3.3"
    }
    humanitec = {
      source  = "humanitec/humanitec"
      version = "~> 1.9"
    }
  }
}
