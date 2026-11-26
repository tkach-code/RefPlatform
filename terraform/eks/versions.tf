terraform {
  required_version = ">= 1.10"

  # State lives in the bootstrap bucket from terraform/s3-state. Pass the
  # account-specific bucket at init:
  #   terraform init -backend-config="bucket=refplatform-tfstate-<account-id>"
  backend "s3" {
    key          = "platform/eks.tfstate"
    region       = "eu-central-1"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
  }
}
