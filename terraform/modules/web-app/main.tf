# One app on the shared platform: namespace + quota, IRSA ServiceAccount,
# optional Secrets Manager secret (CSI-mounted, exposed as env vars),
# Deployment, Service, and an Ingress that joins the shared ALB group.

locals {
  secret_keys = nonsensitive(sort(keys(var.secrets)))
  has_secrets = length(local.secret_keys) > 0
  secret_name = "${var.project}/apps/${var.name}"

  oidc_provider_host = replace(var.oidc_provider_arn, "/^arn:aws[a-z-]*:iam::[0-9]+:oidc-provider\\//", "")

  labels = {
    "app.kubernetes.io/name"       = var.name
    "app.kubernetes.io/part-of"    = var.project
    "app.kubernetes.io/managed-by" = "terraform"
  }
  selector = {
    "app.kubernetes.io/name" = var.name
  }

  tags = merge(var.tags, { App = var.name })
}

# --- namespace and limits ---------------------------------------------------

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name   = var.name
    labels = local.labels
  }
}

resource "kubernetes_resource_quota_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = var.quota.requests_cpu
      "requests.memory" = var.quota.requests_memory
      "limits.cpu"      = var.quota.limits_cpu
      "limits.memory"   = var.quota.limits_memory
      "pods"            = var.quota.pods
    }
  }
}

resource "kubernetes_limit_range_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    limit {
      type = "Container"

      default = {
        cpu    = var.limit_range.default_cpu
        memory = var.limit_range.default_memory
      }

      default_request = {
        cpu    = var.limit_range.default_request_cpu
        memory = var.limit_range.default_request_memory
      }
    }
  }
}

# --- identity and secrets -----------------------------------------------------

data "aws_iam_policy_document" "irsa_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:${var.name}:${var.name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# Always created, so app-specific stacks can attach more policies later.
resource "aws_iam_role" "irsa" {
  name               = "${var.project}-${var.name}-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust.json
  tags               = local.tags
}

resource "aws_secretsmanager_secret" "this" {
  count = local.has_secrets ? 1 : 0

  name                    = local.secret_name
  description             = "${var.name} app secrets (${var.project})"
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "this" {
  count = local.has_secrets ? 1 : 0

  secret_id     = aws_secretsmanager_secret.this[0].id
  secret_string = jsonencode(var.secrets)
}

# Each app can read only its own secret.
resource "aws_iam_role_policy" "read_secret" {
  count = local.has_secrets ? 1 : 0

  name = "read-own-secret"
  role = aws_iam_role.irsa.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = aws_secretsmanager_secret.this[0].arn
    }]
  })
}

resource "kubernetes_service_account_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.irsa.arn
    }
  }
}

# Mounts the secret and syncs it into a Kubernetes Secret named <name>.
resource "kubernetes_manifest" "secret_provider_class" {
  count = local.has_secrets ? 1 : 0

  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = var.name
      namespace = kubernetes_namespace_v1.this.metadata[0].name
    }
    spec = {
      provider = "aws"
      parameters = {
        region = var.aws_region
        objects = yamlencode([
          {
            objectName = local.secret_name
            objectType = "secretsmanager"
            jmesPath = [
              for key in local.secret_keys : {
                path        = key
                objectAlias = key
              }
            ]
          }
        ])
      }
      secretObjects = [
        {
          secretName = var.name
          type       = "Opaque"
          data = [
            for key in local.secret_keys : {
              objectName = key
              key        = key
            }
          ]
        }
      ]
    }
  }

  depends_on = [
    aws_secretsmanager_secret_version.this,
    aws_iam_role_policy.read_secret,
  ]
}

# --- workload -------------------------------------------------------------------

resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = local.selector
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        service_account_name = kubernetes_service_account_v1.this.metadata[0].name

        container {
          name  = var.name
          image = var.image

          port {
            name           = "http"
            container_port = var.container_port
          }

          dynamic "env" {
            for_each = var.env
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "env" {
            for_each = local.secret_keys
            content {
              name = env.value
              value_from {
                secret_key_ref {
                  name = var.name
                  key  = env.value
                }
              }
            }
          }

          dynamic "volume_mount" {
            for_each = local.has_secrets ? [1] : []
            content {
              name       = "secrets-store"
              mount_path = "/mnt/secrets-store"
              read_only  = true
            }
          }

          resources {
            requests = {
              cpu    = var.resources.requests_cpu
              memory = var.resources.requests_memory
            }
            limits = {
              cpu    = var.resources.limits_cpu
              memory = var.resources.limits_memory
            }
          }

          startup_probe {
            http_get {
              path = var.health_path
              port = var.container_port
            }
            period_seconds    = 5
            failure_threshold = 30
          }

          liveness_probe {
            http_get {
              path = var.health_path
              port = var.container_port
            }
            period_seconds = 10
          }

          readiness_probe {
            http_get {
              path = var.health_path
              port = var.container_port
            }
            period_seconds = 10
          }
        }

        dynamic "volume" {
          for_each = local.has_secrets ? [1] : []
          content {
            name = "secrets-store"
            csi {
              driver    = "secrets-store.csi.k8s.io"
              read_only = true
              volume_attributes = {
                secretProviderClass = var.name
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_manifest.secret_provider_class,
    kubernetes_resource_quota_v1.this,
    kubernetes_limit_range_v1.this,
  ]
}

resource "kubernetes_service_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    selector = local.selector

    port {
      name        = "http"
      port        = 80
      target_port = var.container_port
    }
  }
}

# Joins the shared ALB. Don't set load-balancer-name or other "exclusive"
# group annotations here. The platform's shared Ingress owns them.
resource "kubernetes_ingress_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
    annotations = {
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/group.name"       = var.ingress_group_name
      "alb.ingress.kubernetes.io/group.order"      = tostring(var.ingress_order)
      "alb.ingress.kubernetes.io/healthcheck-path" = var.health_path
      "alb.ingress.kubernetes.io/success-codes"    = "200"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    rule {
      http {
        path {
          path      = var.path
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.this.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
