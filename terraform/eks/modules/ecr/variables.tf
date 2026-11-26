variable "repository_name" {
  description = "ECR repository name."
  type        = string
}

variable "tags" {
  description = "Tags applied to ECR resources."
  type        = map(string)
  default     = {}
}

variable "keep_tagged_images" {
  description = "Number of sha- tagged images to keep. Rollback works only to kept tags."
  type        = number
  default     = 15
}
