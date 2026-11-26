data "aws_caller_identity" "current" {}

locals {
  project    = "refplatform"
  account_id = data.aws_caller_identity.current.account_id

  common_tags = {
    Project   = local.project
    Stack     = "bootstrap"
    ManagedBy = "terraform"
  }

  bucket_name = "${local.project}-tfstate-${local.account_id}"
}

# Remote state for every other RefPlatform stack:
#   platform/eks.tfstate   terraform/eks
#   apps/<app>.tfstate     terraform/apps/<app>
# This root keeps its own state locally, because the bucket can't hold state until it exists.
resource "aws_s3_bucket" "state" {
  bucket        = local.bucket_name
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
