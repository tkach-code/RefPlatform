variable "image" {
  description = "Full container image URI including tag (set by CI)."
  type        = string
}

variable "aws_region" {
  description = "AWS region of the platform."
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "Platform EKS cluster."
  type        = string
  default     = "refplatform-eks"
}

variable "admin_email" {
  description = "Admin user created by npm run seed (see terraform/apps/simple-cms/README.md)."
  type        = string
  default     = "admin@refplatform.local"
}
