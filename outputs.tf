output "frontend_storage" {
  value       = module.gui.bucket
  description = "Id and ARN of S3 bucket with app's frontend"
}

output "deployment" {
  value = {
    aws_url           = "${module.api.aws_url}${module.api.stage}"
    stage             = module.api.stage
    custom_domain_url = module.api.url
    user_role_arn     = module.api.user_role.arn
    execution_arn     = module.api.execution_arn
    auth_endpoint     = local.auth_endpoint
  }
  description = "App URL (aws and custom), ARN of api gateway's iam role, api gateway execution ARN, and url of the auth endpoint (if auth is enabled)."
}
