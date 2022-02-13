locals {
  access-log-settings = !var.enable-access-logging ? [] : [{
    log-group-arn = aws_cloudwatch_log_group.access.arn
    log-format    = templatefile("${path.module}/templates/api-access-log-format.json", {})
  }]

  exec-log-settings = [{
    metrics-enabled         = var.enable-execution-logging
    request-logging-enabled = var.log-full-requests
    logging-level           = "INFO"
  }]

  lambda-invocation-arn = "arn:${var.aws-partition}:apigateway:${var.region}:lambda:path/2015-03-31/functions/${var.business-logic.resource-arn}/invocations"
}

#### REST API
resource "aws_api_gateway_rest_api" "api" {
  name           = "${var.name}-rest-api"
  api_key_source = "HEADER"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  minimum_compression_size     = -1
  disable_execute_api_endpoint = true

  tags = var.tags
}

#### API DOMAIN
resource "aws_api_gateway_domain_name" "api" {
  domain_name              = var.domain
  regional_certificate_arn = var.certificate

  security_policy = "TLS_1_2"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
}

resource "aws_route53_record" "api" {
  zone_id = var.domain-zone-id
  name    = aws_api_gateway_domain_name.api.domain_name
  type    = "A"

  alias {
    evaluate_target_health = true
    name                   = aws_api_gateway_domain_name.api.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.api.regional_zone_id
  }
}

#### API DEPLOYMENT
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_rest_api.api.root_resource_id,
      aws_api_gateway_resource.gui-item.id,
      aws_api_gateway_resource.api-item.id,
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.root-get.id,
      aws_api_gateway_method.gui-item-get.id,
      aws_api_gateway_method.gui-item-options.id,
      aws_api_gateway_method.api-item.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_integration.root-get.id,
      aws_api_gateway_integration.gui-item-get.id,
      aws_api_gateway_integration.gui-item-options.id,
      aws_api_gateway_integration.api-item.id,
      aws_api_gateway_integration.proxy.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.api-gateway.arn

  depends_on = [
    aws_cloudwatch_log_group.api,
    aws_cloudwatch_log_group.access,
    aws_iam_role_policy.cloudwatch
  ]
}

resource "aws_api_gateway_stage" "stage" {
  cache_cluster_enabled = false
  deployment_id         = aws_api_gateway_deployment.deployment.id
  rest_api_id           = aws_api_gateway_rest_api.api.id
  stage_name            = var.name
  xray_tracing_enabled  = false

  dynamic "access_log_settings" {
    for_each = toset(local.access-log-settings)
    content {
      destination_arn = access_log_settings.value.log-group-arn
      format          = access_log_settings.value.log-format
    }
  }

  tags = var.tags

  depends_on = [
    aws_api_gateway_account.this
  ]
}

resource "aws_api_gateway_base_path_mapping" "api-mapping" {
  api_id      = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.stage.stage_name
  domain_name = aws_api_gateway_domain_name.api.domain_name
}

resource "aws_api_gateway_method_settings" "api-settings" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.stage.stage_name
  method_path = "*/*"

  dynamic "settings" {
    for_each = toset(local.exec-log-settings)
    content {
      metrics_enabled    = settings.value.metrics-enabled
      data_trace_enabled = settings.value.request-logging-enabled
      logging_level      = settings.value.logging-level
    }
  }

  depends_on = [
    aws_api_gateway_stage.stage
  ]
}

resource "aws_iam_role_policy" "cloudwatch" {
  name = "${var.name}-cloudwatch"
  role = aws_iam_role.api-gateway.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
        "logs:GetLogEvents",
        "logs:FilterLogEvents"
      ],
      Effect = "Allow",
      Resource = [
        "${aws_cloudwatch_log_group.api.arn}:*",
        "${aws_cloudwatch_log_group.access.arn}:*",
        "arn:${var.aws-partition}:logs:${var.region}:${var.aws-account}:log-group:/aws/apigateway/*",
        "arn:${var.aws-partition}:logs:${var.region}:${var.aws-account}:log-group:/aws/apigateway/*:*",
      ]
    }]
  })
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.api.id}/${var.name}"
  retention_in_days = var.log-retention-days
  kms_key_id        = var.shared-kms-key

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "${var.name}-access-logs"
  retention_in_days = var.log-retention-days
  kms_key_id        = var.shared-kms-key

  tags = var.tags
}

resource "aws_api_gateway_resource" "gui-item" {
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{item}"
  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_rest_api.api
  ]
}

resource "aws_api_gateway_resource" "api-item" {
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = var.path
  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_rest_api.api
  ]
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.api-item.id
  path_part   = "{proxy+}"

  depends_on = [
    aws_api_gateway_rest_api.api,
    aws_api_gateway_resource.api-item
  ]
}


#### API GATEWAY METHODS
resource "aws_api_gateway_method" "root-get" {
  api_key_required = "false"
  authorization    = "NONE"
  http_method      = "GET"

  request_parameters = {
    "method.request.header.Content-Disposition" = "false"
    "method.request.header.Content-Type"        = "false"
  }

  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_rest_api.api,
    aws_api_gateway_resource.gui-item,
    aws_api_gateway_resource.api-item
  ]
}

resource "aws_api_gateway_method" "gui-item-get" {
  api_key_required = "false"
  authorization    = "NONE"
  http_method      = "GET"

  request_parameters = {
    "method.request.header.Content-Disposition" = "false"
    "method.request.header.Content-Type"        = "false"
    "method.request.path.item"                  = "true"
  }

  resource_id = aws_api_gateway_resource.gui-item.id
  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_rest_api.api,
    aws_api_gateway_resource.gui-item,
    aws_api_gateway_resource.api-item
  ]
}

resource "aws_api_gateway_method" "gui-item-options" {
  api_key_required = "false"
  authorization    = "NONE"
  http_method      = "OPTIONS"
  resource_id      = aws_api_gateway_resource.gui-item.id
  rest_api_id      = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_rest_api.api,
    aws_api_gateway_resource.gui-item,
    aws_api_gateway_resource.api-item
  ]
}

resource "aws_api_gateway_method" "api-item" {
  api_key_required = "false"
  authorization    = "NONE"
  http_method      = "ANY"
  resource_id      = aws_api_gateway_resource.api-item.id
  rest_api_id      = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_rest_api.api,
    aws_api_gateway_resource.gui-item,
    aws_api_gateway_resource.api-item
  ]
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.proxy" = true
  }

  depends_on = [
    aws_api_gateway_rest_api.api,
    aws_api_gateway_resource.proxy
  ]
}

#### API RESPONSE CONFIGURATION
resource "aws_api_gateway_method_response" "root-get" {
  http_method = "GET"
  resource_id = aws_api_gateway_rest_api.api.root_resource_id

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Content-Disposition" = "false"
    "method.response.header.Content-Type"        = "false"
  }

  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_method.root-get
  ]
}

resource "aws_api_gateway_method_response" "gui-item-get" {
  http_method = "GET"
  resource_id = aws_api_gateway_resource.gui-item.id

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Content-Disposition" = "false"
    "method.response.header.Content-Type"        = "false"
  }

  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_method.gui-item-get
  ]
}

resource "aws_api_gateway_method_response" "gui-item-options" {
  http_method = "OPTIONS"
  resource_id = aws_api_gateway_resource.gui-item.id

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "false"
    "method.response.header.Access-Control-Allow-Methods" = "false"
    "method.response.header.Access-Control-Allow-Origin"  = "false"
  }

  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_method.gui-item-options
  ]
}

resource "aws_api_gateway_method_response" "api-item" {
  http_method = aws_api_gateway_method.api-item.http_method
  resource_id = aws_api_gateway_resource.api-item.id

  response_models = {
    "application/json" = "Empty"
  }

  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_method.api-item
  ]
}

#### API GATEWAY INTEGRATIONS
resource "aws_api_gateway_integration" "root-get" {
  cache_namespace         = aws_api_gateway_rest_api.api.root_resource_id
  connection_type         = "INTERNET"
  credentials             = aws_iam_role.api-gateway.arn
  http_method             = "GET"
  integration_http_method = "GET"
  passthrough_behavior    = "WHEN_NO_MATCH"

  request_parameters = {
    "integration.request.header.Content-Disposition" = "method.request.header.Content-Disposition"
    "integration.request.header.Content-Type"        = "method.request.header.Content-Type"
  }

  resource_id          = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id          = aws_api_gateway_rest_api.api.id
  timeout_milliseconds = "29000"
  type                 = "AWS"
  uri                  = "arn:${var.aws-partition}:apigateway:${var.region}:s3:path/${var.gui-integration.s3-bucket-id}/${var.gui-integration.entrypoint}"

  depends_on = [
    aws_api_gateway_method_response.root-get
  ]

}

resource "aws_api_gateway_integration" "gui-item-get" {
  cache_namespace         = aws_api_gateway_resource.gui-item.id
  connection_type         = "INTERNET"
  credentials             = aws_iam_role.api-gateway.arn
  http_method             = "GET"
  integration_http_method = "GET"
  passthrough_behavior    = "WHEN_NO_MATCH"

  request_parameters = {
    "integration.request.header.Content-Disposition" = "method.request.header.Content-Disposition"
    "integration.request.header.Content-Type"        = "method.request.header.Content-Type"
    "integration.request.path.item"                  = "method.request.path.item"
  }

  resource_id          = aws_api_gateway_resource.gui-item.id
  rest_api_id          = aws_api_gateway_rest_api.api.id
  timeout_milliseconds = "29000"
  type                 = "AWS"
  uri                  = "arn:${var.aws-partition}:apigateway:${var.region}:s3:path/${var.gui-integration.s3-bucket-id}/{item}"


  depends_on = [
    aws_api_gateway_method_response.gui-item-get
  ]
}

resource "aws_api_gateway_integration" "gui-item-options" {
  cache_namespace      = aws_api_gateway_resource.gui-item.id
  connection_type      = "INTERNET"
  http_method          = "OPTIONS"
  passthrough_behavior = "WHEN_NO_MATCH"

  request_templates = {
    "application/json" = jsonencode({
      "statusCode" = 200
    })
  }

  resource_id          = aws_api_gateway_resource.gui-item.id
  rest_api_id          = aws_api_gateway_rest_api.api.id
  timeout_milliseconds = "29000"
  type                 = "MOCK"

  depends_on = [
    aws_api_gateway_method_response.gui-item-options
  ]

}

resource "aws_api_gateway_integration" "api-item" {
  cache_namespace = aws_api_gateway_resource.api-item.id
  resource_id     = aws_api_gateway_resource.api-item.id
  rest_api_id     = aws_api_gateway_rest_api.api.id
  http_method     = aws_api_gateway_method.api-item.http_method

  integration_http_method = "POST"
  passthrough_behavior    = "WHEN_NO_MATCH"
  timeout_milliseconds    = "29000"
  type                    = "AWS_PROXY"
  uri                     = local.lambda-invocation-arn

  depends_on = [
    aws_api_gateway_method_response.api-item
  ]
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_method.proxy.resource_id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = local.lambda-invocation-arn

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }

  depends_on = [
    aws_api_gateway_method.proxy
  ]
}

#### API INTEGRATION RESPONSES
resource "aws_api_gateway_integration_response" "root-get" {
  http_method = "GET"
  resource_id = aws_api_gateway_rest_api.api.root_resource_id

  response_parameters = {
    "method.response.header.Content-Disposition" = "integration.response.header.Content-Disposition"
    "method.response.header.Content-Type"        = "integration.response.header.Content-Type"
  }

  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_integration.root-get
  ]
}

resource "aws_api_gateway_integration_response" "gui-item-get" {
  http_method = "GET"
  resource_id = aws_api_gateway_resource.gui-item.id

  response_parameters = {
    "method.response.header.Content-Disposition" = "integration.response.header.Content-Disposition"
    "method.response.header.Content-Type"        = "integration.response.header.Content-Type"
  }

  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_integration.gui-item-get
  ]
}

resource "aws_api_gateway_integration_response" "gui-item-options" {
  http_method = "OPTIONS"
  resource_id = aws_api_gateway_resource.gui-item.id

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_integration.gui-item-options
  ]
}

resource "aws_api_gateway_integration_response" "api-item" {
  http_method = "ANY"
  resource_id = aws_api_gateway_resource.api-item.id
  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_integration.api-item
  ]
}

resource "aws_api_gateway_integration_response" "proxy" {
  http_method = "ANY"
  resource_id = aws_api_gateway_resource.proxy.id
  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_integration.proxy
  ]
}

#### IAM
resource "aws_iam_role" "api-gateway" {
  name = "${var.name}-api-gateway-role"
  path = "/"

  assume_role_policy   = file("${path.module}/templates/assume-role-api-gw-policy.tmpl.json")
  max_session_duration = "3600"

  tags = var.tags
}
