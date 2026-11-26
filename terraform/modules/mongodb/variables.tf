variable "name" {
  description = "Helm release name."
  type        = string
  default     = "mongodb"
}

variable "namespace" {
  description = "Kubernetes namespace for the MongoDB release (the app's namespace)."
  type        = string
}

variable "storage_class_name" {
  description = "StorageClass for the data volume (platform SSM storage_class_name)."
  type        = string
}

variable "chart_version" {
  description = "Bitnami MongoDB Helm chart version."
  type        = string
  default     = "16.5.45"
}

variable "image_tag" {
  description = "bitnamilegacy/mongodb image tag."
  type        = string
  default     = "7.0.8-debian-12-r2"
}

variable "persistence_size" {
  description = "Persistent volume size for MongoDB."
  type        = string
  default     = "8Gi"
}
