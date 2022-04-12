output "user_role" {
  value = aws_iam_role.api_gateway
}

output "execution_arn" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "authorizer_id" {
  value = local.auth_config.enabled ? aws_api_gateway_authorizer.authorizer[0].id : null
}

output "auth_endpoint" {
  value = local.auth_config.enabled ? local.auth_config.auth_endpoint_path : null
}

output "aws_url" {
  value = aws_api_gateway_deployment.deployment.invoke_url
}

output "url" {
  value = var.domain == null ? "" : "https://${aws_api_gateway_domain_name.api[0].regional_domain_name}"
}

output "stage" {
  value = aws_api_gateway_stage.stage.stage_name
}
