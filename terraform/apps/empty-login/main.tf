# empty-login: demo app at https://<cloudfront>/empty-login.
# Route registry: doc/architecture.md §1.
# App contract (base path, health endpoint, Dockerfile, port 3000): doc/architecture.md §5.

locals {
  app         = "empty-login"
  path        = "/empty-login"
  order       = 110
  health_path = "/empty-login/api/health"
}

module "web_app" {
  source = "../../modules/web-app"

  name          = local.app
  image         = var.image
  replicas      = 1
  path          = local.path
  ingress_order = local.order
  health_path   = local.health_path

  # Plain env vars and secrets (Secrets Manager refplatform/apps/empty-login) for the app:
  env     = {}
  secrets = {}

  ingress_group_name = local.platform.ingress_group_name
  ingress_class_name = local.platform.ingress_class_name
  oidc_provider_arn  = local.platform.oidc_provider_arn
  cluster_name       = var.cluster_name
  aws_region         = var.aws_region
}

# App-specific infrastructure (databases, queues, ...) goes here, in the app's
# namespace (module.web_app.namespace), like terraform/apps/simple-cms does with MongoDB.
