output "secret_name_prefix" {
  description = "Secrets Manager name prefix for app secrets (<project>/apps/)."
  value       = local.secret_name_prefix
}
