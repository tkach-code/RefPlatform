variable "aws_region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "eu-central-1"
}

variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to assume the refplatform-gh-* roles. Empty skips the GitHub OIDC provider and roles."
  type        = string
  default     = ""

  validation {
    condition     = var.github_repository == "" || can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use the form owner/name."
  }
}

variable "create_github_oidc_provider" {
  description = "Create the account-wide token.actions.githubusercontent.com OIDC provider. Set false if it already exists in the account."
  type        = bool
  default     = true
}
