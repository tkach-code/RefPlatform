# GitHub Actions OIDC roles. Workflows build the role ARN from the repository
# variable AWS_ACCOUNT_ID plus these fixed names, so no role secrets are needed:
#   refplatform-gh-build   any ref        push images to ECR refplatform/*
#   refplatform-gh-deploy  main only      terraform/apps/<app> applies
#   refplatform-gh-infra   environments   terraform/eks plan/apply
#                          infra, infra-plan
# Skipped when var.github_repository is empty.

locals {
  github_enabled = var.github_repository != ""
  github_host    = "token.actions.githubusercontent.com"
  cluster_name   = "${local.project}-eks"

  github_provider_arn = local.github_enabled ? (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  ) : ""

  # "repo:OWNER*/REPO*" also matches the expanded sub claim format
  # ("repo:OWNER@id/REPO@id:..."). The exact repository claim is pinned
  # separately in the trust policy.
  github_repo_owner = local.github_enabled ? split("/", var.github_repository)[0] : ""
  github_repo_name  = local.github_enabled ? split("/", var.github_repository)[1] : ""
  github_sub_prefix = "repo:${local.github_repo_owner}*/${local.github_repo_name}*"

  github_role_subjects = {
    build  = ["${local.github_sub_prefix}:*"]
    deploy = ["${local.github_sub_prefix}:ref:refs/heads/main"]
    infra = [
      "${local.github_sub_prefix}:environment:infra",
      "${local.github_sub_prefix}:environment:infra-plan",
    ]
  }
}

# One OIDC provider per account. Set create_github_oidc_provider = false if
# another stack already created token.actions.githubusercontent.com.
resource "aws_iam_openid_connect_provider" "github" {
  count = local.github_enabled && var.create_github_oidc_provider ? 1 : 0

  url            = "https://${local.github_host}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = local.github_enabled && !var.create_github_oidc_provider ? 1 : 0

  url = "https://${local.github_host}"
}

data "aws_iam_policy_document" "github_trust" {
  for_each = local.github_enabled ? local.github_role_subjects : {}

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_host}:repository"
      values   = [var.github_repository]
    }

    condition {
      test     = "StringLike"
      variable = "${local.github_host}:sub"
      values   = each.value
    }
  }
}

resource "aws_iam_role" "github" {
  for_each = data.aws_iam_policy_document.github_trust

  name                 = "${local.project}-gh-${each.key}"
  assume_role_policy   = each.value.json
  max_session_duration = 3600
}

# --- build: push images ---------------------------------------------------

data "aws_iam_policy_document" "build" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = ["arn:aws:ecr:*:${local.account_id}:repository/${local.project}/*"]
  }
}

resource "aws_iam_role_policy" "build" {
  count = local.github_enabled ? 1 : 0

  name   = "build"
  role   = aws_iam_role.github["build"].id
  policy = data.aws_iam_policy_document.build.json
}

# --- deploy: terraform/apps/<app> ------------------------------------------
# Cluster access comes from an EKS access entry in terraform/eks.

data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "StateAppsReadWrite"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/apps/*"]
  }

  statement {
    sid       = "Cluster"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:aws:eks:*:${local.account_id}:cluster/${local.cluster_name}"]
  }

  statement {
    sid       = "Images"
    actions   = ["ecr:DescribeImages"]
    resources = ["arn:aws:ecr:*:${local.account_id}:repository/${local.project}/*"]
  }

  statement {
    sid       = "PlatformParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:*:${local.account_id}:parameter/${local.project}/*"]
  }

  statement {
    sid       = "AppSecrets"
    actions   = ["secretsmanager:*"]
    resources = ["arn:aws:secretsmanager:*:${local.account_id}:secret:${local.project}/apps/*"]
  }

  statement {
    sid       = "IamRead"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid = "AppIrsaRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.project}-*-irsa"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  count = local.github_enabled ? 1 : 0

  name   = "deploy"
  role   = aws_iam_role.github["deploy"].id
  policy = data.aws_iam_policy_document.deploy.json
}

# --- infra: terraform/eks ---------------------------------------------------
# The platform stack creates VPCs, clusters, IAM and CloudFront, so it needs
# broad rights. Only jobs in the GitHub Environments infra / infra-plan can
# assume it. Protect both environments in the repository settings.

resource "aws_iam_role_policy_attachment" "infra" {
  count = local.github_enabled ? 1 : 0

  role       = aws_iam_role.github["infra"].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
