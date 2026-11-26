output "eks_cluster_name" {
  description = "EKS cluster name for kubectl and aws eks commands."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint URL."
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for kubeconfig."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "update_kubeconfig_command" {
  description = "Shell command to configure kubectl for this cluster."
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${module.eks.cluster_name}"
}

output "public_base_url" {
  description = "Public HTTPS entry point for all apps (CloudFront). Apps are at <url>/<app>/."
  value       = "https://${module.cloudfront.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "Shared CloudFront distribution ID."
  value       = module.cloudfront.distribution_id
}

output "alb_dns_name" {
  description = "AWS-generated hostname of the shared ALB (HTTP only, CloudFront origin)."
  value       = module.ingress.alb_dns_name
}

output "ecr_repository_urls" {
  description = "ECR repository URL per app."
  value       = { for app, m in module.ecr : app => m.repository_url }
}

output "ecr_login_command" {
  description = "Shell command to authenticate Docker to this account's ECR registry."
  value       = "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${local.platform_parameters.ecr_registry}"
}

output "ingress_group_name" {
  description = "Ingress group app Ingresses join to share the ALB."
  value       = module.ingress.ingress_group_name
}

output "ingress_class_name" {
  description = "Ingress class app Ingresses use."
  value       = module.ingress.ingress_class_name
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for IRSA."
  value       = module.eks.oidc_provider_arn
}

output "secret_name_prefix" {
  description = "Secrets Manager prefix for app secrets (refplatform/apps/<app>)."
  value       = module.secrets_store.secret_name_prefix
}

output "platform_parameter_names" {
  description = "SSM parameters app stacks read."
  value       = [for p in aws_ssm_parameter.platform : p.name]
}

output "cluster_admin_principal_arns" {
  description = "Principals with EKS cluster admin access entries."
  value       = local.cluster_admin_principal_arns
}
