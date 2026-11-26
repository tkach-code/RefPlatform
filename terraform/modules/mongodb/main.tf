# Standalone Bitnami MongoDB in an app's namespace. Uses the platform
# StorageClass (refplatform-gp3). The chart's default image no longer pulls,
# so the tag is pinned on bitnamilegacy.

resource "random_password" "root" {
  length  = 32
  special = false
}

locals {
  # Bitnami names resources after the release when it already contains the chart name.
  service_name = strcontains(var.name, "mongodb") ? var.name : "${var.name}-mongodb"
}

resource "helm_release" "this" {
  name       = var.name
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "mongodb"
  version    = var.chart_version
  namespace  = var.namespace
  timeout    = 600

  values = [
    yamlencode({
      architecture = "standalone"
      image = {
        registry   = "docker.io"
        repository = "bitnamilegacy/mongodb"
        tag        = var.image_tag
      }
      global = {
        security = {
          allowInsecureImages = true
        }
      }
      auth = {
        enabled = true
      }
      persistence = {
        enabled      = true
        size         = var.persistence_size
        storageClass = var.storage_class_name
      }
      resources = {
        requests = {
          cpu    = "250m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }
    })
  ]

  set_sensitive {
    name  = "auth.rootPassword"
    value = random_password.root.result
  }
}
