output "user-role" {
    value = aws_iam_role.api-gateway
}

output "execution-arn" {
    value = aws_api_gateway_rest_api.api.execution_arn
}
