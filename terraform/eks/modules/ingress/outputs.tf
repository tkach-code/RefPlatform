output "alb_dns_name" {
  description = "AWS-generated hostname of the shared internet-facing ALB."
  value       = kubernetes_ingress_v1.public.status[0].load_balancer[0].ingress[0].hostname
}

output "ingress_group_name" {
  description = "Ingress group name later apps use to share this ALB."
  value       = local.ingress_group_name
}

output "ingress_class_name" {
  description = "Ingress class later apps set on their Ingress resources."
  value       = local.ingress_class_name
}

output "ingress_namespace" {
  description = "Namespace of the shared Ingress and its catch-all 404 rule."
  value       = local.ingress_namespace
}

output "load_balancer_name" {
  description = "AWS name of the shared ALB."
  value       = local.load_balancer_name
}
