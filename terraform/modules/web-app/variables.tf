variable "project" {
  description = "Platform name used in AWS resource names."
  type        = string
  default     = "refplatform"
}

variable "name" {
  description = "App name: namespace, Deployment/Service/Ingress name, IRSA role refplatform-<name>-irsa, secret refplatform/apps/<name>."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.name))
    error_message = "Lowercase letters, digits and dashes, 2-20 characters, starting with a letter."
  }
}

variable "image" {
  description = "Full container image reference including tag."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 3000
}

variable "replicas" {
  description = "Number of pods."
  type        = number
  default     = 1
}

variable "resources" {
  description = "Container requests and limits."
  type = object({
    requests_cpu    = string
    requests_memory = string
    limits_cpu      = string
    limits_memory   = string
  })
  default = {
    requests_cpu    = "50m"
    requests_memory = "128Mi"
    limits_cpu      = "500m"
    limits_memory   = "256Mi"
  }
}

variable "quota" {
  description = "Namespace ResourceQuota (covers the app and anything else in its namespace, such as databases)."
  type = object({
    requests_cpu    = string
    requests_memory = string
    limits_cpu      = string
    limits_memory   = string
    pods            = string
  })
  default = {
    requests_cpu    = "500m"
    requests_memory = "1Gi"
    limits_cpu      = "2"
    limits_memory   = "2Gi"
    pods            = "10"
  }
}

variable "limit_range" {
  description = "Default requests/limits for containers in the namespace that don't set their own."
  type = object({
    default_cpu            = string
    default_memory         = string
    default_request_cpu    = string
    default_request_memory = string
  })
  default = {
    default_cpu            = "500m"
    default_memory         = "512Mi"
    default_request_cpu    = "100m"
    default_request_memory = "256Mi"
  }
}

variable "path" {
  description = "URL path prefix the app owns on the shared host: \"/<name>\", or \"/\" for the landing page. The ALB forwards it unchanged."
  type        = string

  validation {
    condition     = var.path == "/" || can(regex("^/[a-z0-9-]+$", var.path))
    error_message = "Use \"/\" or \"/<segment>\" without a trailing slash."
  }
}

variable "ingress_order" {
  description = "ALB group.order (lower is evaluated first). Unique per app, < 1000. The \"/\" app must have the highest order."
  type        = number

  validation {
    condition     = var.ingress_order >= 1 && var.ingress_order < 1000
    error_message = "Use 1-999. 1000 is the platform catch-all."
  }
}

variable "health_path" {
  description = "Full HTTP path for pod probes and the ALB health check, including the path prefix (e.g. /simple-cms/api/health)."
  type        = string
}

variable "ingress_group_name" {
  description = "Shared ALB Ingress group (platform SSM ingress_group_name)."
  type        = string
}

variable "ingress_class_name" {
  description = "Ingress class (platform SSM ingress_class_name)."
  type        = string
}

variable "env" {
  description = "Plain environment variables."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secret environment variables. Stored in Secrets Manager refplatform/apps/<name>, mounted via the CSI driver, and exposed as env vars. Keys must be known at plan time."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "aws_region" {
  description = "AWS region (SecretProviderClass)."
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS IAM OIDC provider ARN for IRSA (platform SSM oidc_provider_arn)."
  type        = string
}

variable "tags" {
  description = "Tags for AWS resources."
  type        = map(string)
  default     = {}
}
