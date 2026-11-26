variable "name" {
  description = "Name used to identify the CloudFront distribution."
  type        = string
}

variable "origin_domain_name" {
  description = "DNS hostname of the application load balancer."
  type        = string
}

variable "tags" {
  description = "Tags applied to the CloudFront distribution."
  type        = map(string)
  default     = {}
}