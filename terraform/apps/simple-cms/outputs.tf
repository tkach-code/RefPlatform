output "url" {
  description = "Public URL of the app."
  value       = "${local.platform.public_base_url}${local.path}/"
}

output "admin_url" {
  description = "Admin sign-in page."
  value       = "${local.platform.public_base_url}${local.path}/admin/login"
}

output "image" {
  description = "Deployed image (used by apps-redeploy-all)."
  value       = module.web_app.image
}

output "admin_email" {
  description = "Seeded admin email."
  value       = var.admin_email
}

output "admin_password" {
  description = "Generated admin password: terraform output -raw admin_password"
  value       = random_password.admin.result
  sensitive   = true
}

output "secret_name" {
  description = "Secrets Manager secret holding the app's env secrets."
  value       = module.web_app.secret_name
}
