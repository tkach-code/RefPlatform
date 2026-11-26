output "namespace" {
  description = "App namespace."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "service_name" {
  description = "ClusterIP Service name (port 80)."
  value       = kubernetes_service_v1.this.metadata[0].name
}

output "path" {
  description = "URL path prefix on the shared host."
  value       = var.path
}

output "image" {
  description = "Deployed container image."
  value       = var.image
}

output "irsa_role_arn" {
  description = "IAM role assumed by the app's ServiceAccount."
  value       = aws_iam_role.irsa.arn
}

output "irsa_role_name" {
  description = "IAM role name, for attaching extra app-specific policies."
  value       = aws_iam_role.irsa.name
}

output "secret_name" {
  description = "Secrets Manager secret name (null when the app has no secrets)."
  value       = local.has_secrets ? local.secret_name : null
}
