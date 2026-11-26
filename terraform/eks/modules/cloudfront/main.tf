# Shared public entry point: https://<generated>.cloudfront.net -> shared ALB (HTTP).
# Every path goes to the ALB unchanged, and the ALB routes /<app>* to each app.

locals {
  origin_id = "${var.name}-alb"

  # AWS managed policies
  caching_disabled_policy_id  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
  caching_optimized_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  all_viewer_request_policy   = "216adef6-5c7f-47e4-b989-5492eafa07d3" # AllViewer (forwards Host, cookies, query)
  security_headers_policy_id  = "67f7725c-6f97-4210-82d7-5512b31e9d03" # SecurityHeadersPolicy
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  comment         = var.name
  is_ipv6_enabled = true
  price_class     = "PriceClass_100"
  http_version    = "http2"

  origin {
    domain_name = var.origin_domain_name
    origin_id   = local.origin_id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Dynamic app traffic: no caching, everything forwarded.
  default_cache_behavior {
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = local.caching_disabled_policy_id
    origin_request_policy_id   = local.all_viewer_request_policy
    response_headers_policy_id = local.security_headers_policy_id
  }

  # Next.js build assets (content-hashed file names) for every app:
  # /<app>/_next/static/* and /_next/static/* (index-app).
  ordered_cache_behavior {
    path_pattern           = "*/_next/static/*"
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = local.caching_optimized_policy_id
    response_headers_policy_id = local.security_headers_policy_id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(var.tags, {
    Name = var.name
  })
}
