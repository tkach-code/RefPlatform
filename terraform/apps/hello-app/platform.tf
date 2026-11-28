# Shared platform values published by terraform/eks as SSM parameters.
locals {
  platform_parameter_names = [
    "public_base_url",
    "ingress_group_name",
    "ingress_class_name",
    "oidc_provider_arn",
    "storage_class_name",
  ]
}

data "aws_ssm_parameter" "platform" {
  for_each = toset(local.platform_parameter_names)

  name = "/refplatform/platform/${each.key}"
}

locals {
  platform = { for k, p in data.aws_ssm_parameter.platform : k => nonsensitive(p.value) }
}
