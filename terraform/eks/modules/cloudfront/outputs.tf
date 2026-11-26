output "domain_name" {
  description = "Generated HTTPS-capable CloudFront hostname."
  value       = aws_cloudfront_distribution.this.domain_name
}
output "distribution_id" {
  description = "CloudFront distribution ID (for cache invalidations)."
  value       = aws_cloudfront_distribution.this.id
}
