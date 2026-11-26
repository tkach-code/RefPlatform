# Secrets Store CSI Driver + AWS provider (ASCP). App stacks create their own
# secret under <project>/apps/<app> and an IRSA role with an inline policy that
# reads only that secret (terraform/modules/web-app).

locals {
  secret_name_prefix = "${var.project}/apps/"
}

# Secrets Store CSI Driver (syncs mounted secrets into Kubernetes Secrets).
resource "helm_release" "secrets_store_csi_driver" {
  name       = "csi-secrets-store"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"
  version    = "1.6.1"

  set {
    name  = "syncSecret.enabled"
    value = "true"
  }

  set {
    name  = "enableSecretRotation"
    value = "true"
  }

  # Kubelet only attaches a service account token when the CSIDriver asks for
  # one. The AWS provider reads that token to call STS.
  set {
    name  = "tokenRequests[0].audience"
    value = "sts.amazonaws.com"
  }
}

# AWS Secrets and Configuration Provider (ASCP) for Secrets Manager.
resource "helm_release" "secrets_store_csi_driver_provider_aws" {
  name       = "secrets-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  namespace  = "kube-system"
  version    = "3.1.3"

  set {
    name  = "secrets-store-csi-driver.install"
    value = "false"
  }

  depends_on = [helm_release.secrets_store_csi_driver]
}
