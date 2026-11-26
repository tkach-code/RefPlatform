data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Role behind the current credentials (for assumed roles, the role, not the session).
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  project      = "refplatform"
  cluster_name = "${local.project}-eks"
  account_id   = data.aws_caller_identity.current.account_id

  common_tags = {
    Project   = local.project
    Stack     = "platform"
    ManagedBy = "terraform"
  }

  # GitHub Actions roles from terraform/s3-state (refplatform-gh-*).
  github_ci_admin_role_arns = var.github_ci_roles_enabled ? [
    "arn:aws:iam::${local.account_id}:role/${local.project}-gh-infra",
    "arn:aws:iam::${local.account_id}:role/${local.project}-gh-deploy",
  ] : []

  # Explicit admins + CI roles + whoever runs this apply. The last one keeps a
  # first local apply from locking itself out. List your own principal in
  # cluster_admin_principal_arns, or a later CI apply removes its access entry.
  cluster_admin_principal_arns = distinct(concat(
    var.cluster_admin_principal_arns,
    local.github_ci_admin_role_arns,
    [data.aws_iam_session_context.current.issuer_arn],
  ))
}

# Dedicated VPC: public/private subnets, NAT, and IGW for EKS.
module "vpc" {
  source = "./modules/vpc"

  name     = "${local.project}-vpc"
  vpc_cidr = var.vpc_cidr
  tags     = local.common_tags
}

# One immutable ECR repository per app (see apps.tf).
module "ecr" {
  source   = "./modules/ecr"
  for_each = toset(local.apps)

  repository_name = "${local.project}/${each.key}"
  tags            = merge(local.common_tags, { App = each.key })
}

# EKS cluster, node group, add-ons, OIDC, and access entries.
module "eks" {
  source = "./modules/eks"

  cluster_name                 = local.cluster_name
  cluster_version              = var.cluster_version
  vpc_id                       = module.vpc.vpc_id
  private_subnet_ids           = module.vpc.private_subnet_ids
  public_subnet_ids            = module.vpc.public_subnet_ids
  cluster_admin_principal_arns = local.cluster_admin_principal_arns
  node_instance_types          = var.node_instance_types
  node_desired_size            = var.node_desired_size
  node_max_size                = var.node_max_size
  tags                         = local.common_tags
}

# AWS Load Balancer Controller and the shared internet-facing Ingress (ALB refplatform-alb).
module "ingress" {
  source = "./modules/ingress"

  project                               = local.project
  cluster_name                          = module.eks.cluster_name
  region                                = data.aws_region.current.name
  vpc_id                                = module.vpc.vpc_id
  aws_load_balancer_controller_role_arn = module.eks.aws_load_balancer_controller_role_arn
  internet_gateway_id                   = module.vpc.igw_id

  depends_on = [module.eks]
}

# Secrets Store CSI Driver and AWS provider (ASCP) for app secrets.
module "secrets_store" {
  source = "./modules/secrets_store"

  project = local.project

  depends_on = [module.eks]
}

# Single public HTTPS entry point for every app, in front of the shared ALB.
module "cloudfront" {
  source = "./modules/cloudfront"

  name               = "${local.project}-cdn"
  origin_domain_name = module.ingress.alb_dns_name
  tags               = local.common_tags
}

# Cluster-wide gp3 StorageClass for app databases. The EBS CSI driver add-on
# doesn't create a default StorageClass.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "${local.project}-gp3"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type   = "gp3"
    fsType = "ext4"
  }

  depends_on = [module.eks]
}

# Values app stacks read with aws_ssm_parameter data sources, so they don't
# depend on this stack's state.
locals {
  platform_parameters = {
    cluster_name       = module.eks.cluster_name
    public_base_url    = "https://${module.cloudfront.domain_name}"
    alb_hostname       = module.ingress.alb_dns_name
    ingress_group_name = module.ingress.ingress_group_name
    ingress_class_name = module.ingress.ingress_class_name
    oidc_provider_arn  = module.eks.oidc_provider_arn
    secret_name_prefix = module.secrets_store.secret_name_prefix
    storage_class_name = kubernetes_storage_class_v1.gp3.metadata[0].name
    ecr_registry       = "${local.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
  }
}

resource "aws_ssm_parameter" "platform" {
  for_each = local.platform_parameters

  name  = "/${local.project}/platform/${each.key}"
  type  = "String"
  value = each.value
}
