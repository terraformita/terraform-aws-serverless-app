locals {
  api-path-part = substr(var.api.path, 1, length(var.api.path) - 1)
}

module "gui" {
  source = "./gui"

  name           = var.name
  tags           = var.tags
  files          = var.gui.source.files
  s3-logs-bucket = var.s3-logs-bucket
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
      aws_api_gateway_method.root-get.id,
      aws_api_gateway_method.gui-item-get.id,
      aws_api_gateway_method.gui-item-options.id,
      aws_api_gateway_method.api-item-get.id,
      aws_api_gateway_integration.root-get.id,
      aws_api_gateway_integration.gui-item-get.id,
      aws_api_gateway_integration.gui-item-options.id,
      aws_api_gateway_integration.api-item-get.id
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

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format          = templatefile("${path.module}/templates/api-access-log-format.json", {})
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

resource "aws_api_gateway_method_settings" "example" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.stage.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = true
    data_trace_enabled = true
    logging_level      = "INFO"
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
        "logs:PutLogEvents",
        "logs:CreateLogStream"
      ],
      Effect = "Allow",
      Resource = [
        "${aws_cloudwatch_log_group.api.arn}:*",
        "${aws_cloudwatch_log_group.access.arn}:*"
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
  path_part   = local.api-path-part
  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_rest_api.api
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

resource "aws_api_gateway_method" "api-item-get" {
  api_key_required = "false"
  authorization    = "NONE"
  http_method      = "GET"
  resource_id      = aws_api_gateway_resource.api-item.id
  rest_api_id      = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_rest_api.api,
    aws_api_gateway_resource.gui-item,
    aws_api_gateway_resource.api-item
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

resource "aws_api_gateway_method_response" "api-item-get" {
  http_method = "GET"
  resource_id = aws_api_gateway_resource.api-item.id

  response_models = {
    "application/json" = "Empty"
  }

  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_method.api-item-get
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
  uri                  = "arn:${var.aws-partition}:apigateway:${var.region}:s3:path/${module.gui.out.s3-bucket-id}/${var.gui.entrypoint}"

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
  uri                  = "arn:${var.aws-partition}:apigateway:${var.region}:s3:path/${module.gui.out.s3-bucket-id}/{item}"


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

resource "aws_api_gateway_integration" "api-item-get" {
  cache_namespace         = aws_api_gateway_resource.api-item.id
  connection_type         = "INTERNET"
  content_handling        = "CONVERT_TO_TEXT"
  http_method             = "GET"
  integration_http_method = "POST"
  passthrough_behavior    = "WHEN_NO_MATCH"
  resource_id             = aws_api_gateway_resource.api-item.id
  rest_api_id             = aws_api_gateway_rest_api.api.id
  timeout_milliseconds    = "29000"
  type                    = "AWS_PROXY"
  uri                     = "arn:${var.aws-partition}:apigateway:${var.region}:lambda:path/2015-03-31/functions/${var.api.business-logic.resource.arn}/invocations"

  depends_on = [
    aws_api_gateway_method_response.api-item-get
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

resource "aws_api_gateway_integration_response" "api-item-get" {
  http_method = "GET"
  resource_id = aws_api_gateway_resource.api-item.id
  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_integration.api-item-get
  ]
}

#### IAM
resource "aws_iam_role" "api-gateway" {
  name = "${var.name}-api-gateway-role"
  path = "/"

  assume_role_policy   = templatefile("${path.module}/templates/assume-role-api-gw.pol", {})
  max_session_duration = "3600"

  tags = var.tags
}

#### API ACCESS TO GUI BUCKET
resource "aws_iam_policy" "gui-bucket" {
  name   = "${var.name}-gui-bucket-access"
  policy = data.aws_iam_policy_document.gui-bucket.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "gui-bucket" {
  role       = aws_iam_role.api-gateway.name
  policy_arn = aws_iam_policy.gui-bucket.arn
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.api-gateway.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

data "aws_iam_policy_document" "gui-bucket" {
  statement {
    actions = [
      "s3:ListBucket"
    ]

    resources = [
      module.gui.out.s3-bucket-arn
    ]
  }

  statement {
    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${module.gui.out.s3-bucket-arn}/*"
    ]
  }
}

#### BUSINESS LOGIC CALLING PERMISSIONS
resource "aws_lambda_permission" "business-logic" {
  action        = "lambda:InvokeFunction"
  function_name = var.api.business-logic.resource.function-name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/*/GET/${local.api-path-part}"
}
