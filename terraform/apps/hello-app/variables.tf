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
