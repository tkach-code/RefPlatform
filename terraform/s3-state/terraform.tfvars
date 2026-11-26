# Copied from terraform.tfvars.example. Committed: holds no secrets.
aws_region = "eu-central-1"

# GitHub repository (owner/name) whose Actions may assume the refplatform-gh-* roles.
# Leave empty to skip the GitHub OIDC provider and roles.
github_repository = "tkach-code/RefPlatform"

# Set false if the account already has the token.actions.githubusercontent.com provider
# (for example, created by hand for an earlier project).
create_github_oidc_provider = false
