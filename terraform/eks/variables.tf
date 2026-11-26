variable "aws_region" {
  description = "AWS region for all resources. Must match the backend region in versions.tf."
  type        = string
  default     = "eu-central-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the platform VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_version" {
  description = "EKS Kubernetes version. Bump when AWS publishes newer EKS versions."
  type        = string
  default     = "1.36"
}

variable "cluster_admin_principal_arns" {
  description = "IAM user/role ARNs (not assumed-role session ARNs) granted EKS cluster admin. Put your own principal here."
  type        = list(string)
  default     = []
}

variable "github_ci_roles_enabled" {
  description = "Grant cluster admin to the refplatform-gh-infra and refplatform-gh-deploy roles. They must exist (terraform/s3-state with github_repository set)."
  type        = bool
  default     = true
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired node count. Size for the sum of all apps' requests."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum node count."
  type        = number
  default     = 3
}
