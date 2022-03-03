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
