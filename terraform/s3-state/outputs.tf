output "bucket_name" {
  description = "S3 bucket that holds the platform and app Terraform state."
  value       = aws_s3_bucket.state.id
}

output "bucket_region" {
  description = "Region of the state bucket."
  value       = var.aws_region
}

output "account_id" {
  description = "AWS account ID. Set it as the GitHub repository variable AWS_ACCOUNT_ID."
  value       = local.account_id
}

output "github_role_arns" {
  description = "GitHub Actions OIDC roles (empty when github_repository is not set)."
  value       = { for k, r in aws_iam_role.github : k => r.arn }
}
