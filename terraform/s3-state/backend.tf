# State lives in the bucket this stack creates (key bootstrap/s3-state.tfstate):
#   terraform init -backend-config="bucket=refplatform-tfstate-<account-id>"
#
# The bucket can't hold state before it exists, and can't keep it while it is
# being destroyed. For the first apply in a new account, and before a destroy,
# rename this file to backend.tf.off so the stack runs on local state. See README.md.
terraform {
  backend "s3" {
    key          = "bootstrap/s3-state.tfstate"
    region       = "eu-central-1"
    use_lockfile = true
    encrypt      = true
  }
}
