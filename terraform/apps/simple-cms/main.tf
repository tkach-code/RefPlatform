# simple-cms: Next.js CMS demo at https://<cloudfront>/simple-cms with its own MongoDB.
# Route registry: doc/multi-app-platform-plan.md §1.

locals {
  app         = "simple-cms"
  path        = "/simple-cms" # must match basePath in apps/simple-cms/next.config.ts
  order       = 100
  health_path = "/simple-cms/api/health"
  database    = "simple-cms"
}

resource "random_password" "auth" {
  length  = 32
  special = false
}

resource "random_password" "admin" {
  length  = 24
  special = false
}

module "web_app" {
  source = "../../modules/web-app"

  name          = local.app
  image         = var.image
  replicas      = 2
  path          = local.path
  ingress_order = local.order
  health_path   = local.health_path

  resources = {
    requests_cpu    = "100m"
    requests_memory = "256Mi"
    limits_cpu      = "500m"
    limits_memory   = "512Mi"
  }

  # 2-3 app pods (rolling update) + MongoDB (250m/512Mi requests, 1 CPU/1Gi limits).
  quota = {
    requests_cpu    = "1"
    requests_memory = "2Gi"
    limits_cpu      = "4"
    limits_memory   = "4Gi"
    pods            = "10"
  }

  env = {
    # Origin only: Auth.js gets its base path (/simple-cms/api/auth) from
    # lib/auth.config.ts. Needed because the ALB reports http, not CloudFront's https.
    AUTH_URL = local.platform.public_base_url
  }

  secrets = {
    MONGODB_URI    = "mongodb://root:${module.mongodb.root_password}@${module.mongodb.host}/${local.database}?authSource=admin"
    AUTH_SECRET    = random_password.auth.result
    ADMIN_EMAIL    = var.admin_email
    ADMIN_PASSWORD = random_password.admin.result
  }

  ingress_group_name = local.platform.ingress_group_name
  ingress_class_name = local.platform.ingress_class_name
  oidc_provider_arn  = local.platform.oidc_provider_arn
  cluster_name       = var.cluster_name
  aws_region         = var.aws_region
}

module "mongodb" {
  source = "../../modules/mongodb"

  namespace          = module.web_app.namespace
  storage_class_name = local.platform.storage_class_name
}
