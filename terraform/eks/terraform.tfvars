aws_region      = "eu-central-1"
cluster_version = "1.37"

# Your own IAM user/role ARN, so CI applies don't remove your cluster access.
# Example: "arn:aws:iam::123456789012:user/me" or "arn:aws:iam::123456789012:role/Admin"
cluster_admin_principal_arns = ["arn:aws:iam::763788640069:user/aws-test-user"]

# Set false if terraform/s3-state was applied without github_repository.
github_ci_roles_enabled = true
