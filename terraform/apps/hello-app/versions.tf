terraform {
  required_version = ">= 1.10"

  # Pass the account-specific bucket at init:
  #   terraform init -backend-config="bucket=refplatform-tfstate-<account-id>"
  backend "s3" {
    key          = "apps/hello-app.tfstate"
    region       = "eu-central-1"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
  }
}
