output "service_name" {
  description = "MongoDB Service name in the namespace."
  value       = local.service_name
}

output "host" {
  description = "In-cluster MongoDB host:port."
  value       = "${local.service_name}.${var.namespace}.svc.cluster.local:27017"
}

output "root_password" {
  description = "MongoDB root password."
  value       = random_password.root.result
  sensitive   = true
}

output "release_name" {
  description = "Helm release name."
  value       = helm_release.this.name
}
