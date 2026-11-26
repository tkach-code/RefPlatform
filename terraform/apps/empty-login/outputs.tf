output "url" {
  description = "Public URL of the app."
  value       = "${local.platform.public_base_url}${trimsuffix(local.path, "/")}/"
}

output "image" {
  description = "Deployed image (used by apps-redeploy-all)."
  value       = module.web_app.image
}
