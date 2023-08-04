locals {
  access-log-settings = !local.logging_config.enable_access_logging ? [] : [{
    log_group_arn = aws_cloudwatch_log_group.access.arn
    log_format    = templatefile("${path.module}/templates/api-access-log-format.json", {})
  }]

  exec_log_settings = [{
    metrics_enabled         = local.logging_config.enable_execution_logging
    request_logging_enabled = local.logging_config.log_full_requests
    logging_level           = "INFO"
  }]

  invocation_arn_template = "arn:${var.aws_partition}:apigateway:${var.region}:lambda:path/2015-03-31/functions/{FUNCTION_ARN}/invocations"

  lambda_invocation_arn     = replace(local.invocation_arn_template, "{FUNCTION_ARN}", var.business_logic.function_arn)
  authorizer_invocation_arn = local.auth_enabled ? replace(local.invocation_arn_template, "{FUNCTION_ARN}", var.auth_config.authorizer.function_arn) : ""

  auth_config    = module.auth_defaults.output
  logging_config = module.logging_defaults.output

  auth_config_present = !(var.auth_config == null)
  auth_enabled        = local.auth_config_present ? var.auth_config.enabled : false
}

module "auth_defaults" {
  source  = "terraformita/defaults/local"
  version = "0.0.6"

  input = var.auth_config
  defaults = {
    enabled = false
  }
}

module "logging_defaults" {
  source  = "terraformita/defaults/local"
  version = "0.0.6"

  input = var.logging_config
  defaults = {
    enable_access_logging    = true
    enable_execution_logging = false
    log_full_requests        = false
    log_retention_days       = 7
  }
}


#### REST API
resource "aws_api_gateway_rest_api" "api" {
  name           = "${var.name}-rest-api"
  api_key_source = "HEADER"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  binary_media_types = var.binary_media_types

  minimum_compression_size     = -1
  disable_execute_api_endpoint = var.disable_aws_url

  tags = var.tags
}

#### API DOMAIN
resource "aws_api_gateway_domain_name" "api" {
  count = var.domain == null ? 0 : 1

  domain_name              = var.domain
  regional_certificate_arn = var.certificate

  security_policy = "TLS_1_2"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
}

resource "aws_route53_record" "api" {
  count   = var.domain_zone_id != null ? 1 : 0
  zone_id = var.domain_zone_id
  name    = aws_api_gateway_domain_name.api[0].domain_name
  type    = "A"


  alias {
    evaluate_target_health = true
    name                   = aws_api_gateway_domain_name.api[0].regional_domain_name
    zone_id                = aws_api_gateway_domain_name.api[0].regional_zone_id
  }
}

#### API DEPLOYMENT
resource "random_id" "trigger" {
  byte_length = 8

  keepers = {
    uuid = uuid()
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = element(concat(random_id.trigger.*.hex, []), 0)
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.root_get,
    aws_api_gateway_method.s3_proxy_get,
    # aws_api_gateway_method.gui_item_options,
    aws_api_gateway_method.api_item,
    aws_api_gateway_method.proxy,
    aws_api_gateway_resource.s3_proxy,
    aws_api_gateway_resource.api_item,
    aws_api_gateway_resource.proxy,
    aws_api_gateway_method_response.root_get,
    aws_api_gateway_method_response.s3_proxy_get,
    # aws_api_gateway_method_response.gui_item_options,
    aws_api_gateway_method_response.api_item,
    aws_api_gateway_integration.root_get,
    aws_api_gateway_integration.s3_proxy_get,
    aws_api_gateway_integration.api_item,
    aws_api_gateway_integration.proxy,
    aws_api_gateway_integration_response.root_get,
    aws_api_gateway_integration_response.s3_proxy_get,
    aws_api_gateway_integration_response.api_item,
    aws_api_gateway_integration_response.proxy
  ]
}

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.api_gateway.arn

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
  stage_name            = var.stage_name
  xray_tracing_enabled  = false

  dynamic "access_log_settings" {
    for_each = toset(local.access-log-settings)
    content {
      destination_arn = access_log_settings.value.log_group_arn
      format          = access_log_settings.value.log_format
    }
  }

  tags = var.tags

  depends_on = [
    aws_api_gateway_account.this
  ]
}

resource "aws_api_gateway_base_path_mapping" "api_mapping" {
  count = var.domain == null ? 0 : 1

  api_id      = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.stage.stage_name
  domain_name = aws_api_gateway_domain_name.api[0].domain_name
}

resource "aws_api_gateway_method_settings" "api_settings" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.stage.stage_name
  method_path = "*/*"

  dynamic "settings" {
    for_each = toset(local.exec_log_settings)
    content {
      metrics_enabled    = settings.value.metrics_enabled
      data_trace_enabled = settings.value.request_logging_enabled
      logging_level      = settings.value.logging_level
    }
  }

  depends_on = [
    aws_api_gateway_stage.stage
  ]
}

resource "aws_iam_role_policy" "cloudwatch" {
  name = "${var.name}-cloudwatch"
  role = aws_iam_role.api_gateway.id

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
        "arn:${var.aws_partition}:logs:${var.region}:${var.aws_account_id}:log-group:/aws/apigateway/*",
        "arn:${var.aws_partition}:logs:${var.region}:${var.aws_account_id}:log-group:/aws/apigateway/*:*",
      ]
    }]
  })
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "api_gateway-Execution-Logs_${aws_api_gateway_rest_api.api.id}/${var.name}"
  retention_in_days = local.logging_config.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "${var.name}-access-logs"
  retention_in_days = local.logging_config.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = var.tags
}

#### DEFAULT API RESPONSES
resource "aws_api_gateway_gateway_response" "unauthorized" {
  count         = local.auth_enabled ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.api.id
  status_code   = "302"
  response_type = "UNAUTHORIZED"

  response_templates = {
    "application/json" = "{\"message\":$context.error.messageString}"
  }

  response_parameters = {
    "gatewayresponse.header.Location" = "'${var.auth_config.login_url}'"
  }
}

resource "aws_api_gateway_gateway_response" "access_denied" {
  count         = local.auth_enabled ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.api.id
  status_code   = "302"
  response_type = "ACCESS_DENIED"

  response_templates = {
    "application/json" = "{\"message\":$context.error.messageString}"
  }

  response_parameters = {
    "gatewayresponse.header.Location" = "'${var.auth_config.login_url}'"
  }
}

#### LAMBDA AUTHORIZER
resource "aws_api_gateway_authorizer" "authorizer" {
  count                  = local.auth_enabled ? 1 : 0
  name                   = "${var.name}-auth-authorizer"
  type                   = "REQUEST"
  rest_api_id            = aws_api_gateway_rest_api.api.id
  authorizer_uri         = local.authorizer_invocation_arn
  authorizer_credentials = aws_iam_role.authorizer[0].arn
  identity_source        = "method.request.header.Cookie"

  depends_on = [
    aws_iam_role_policy.authorizer
  ]
}

resource "aws_iam_role" "authorizer" {
  count = local.auth_enabled ? 1 : 0
  name  = "${var.name}-authorizer-invocation-role"

  assume_role_policy = file("${path.module}/templates/assume-role-api-gw-policy.tmpl.json")

  tags = var.tags
}

resource "aws_iam_role_policy" "authorizer" {
  count = local.auth_enabled ? 1 : 0
  name  = "${var.name}-authorizer-invocation-policy"
  role  = aws_iam_role.authorizer[0].id

  policy = templatefile("${path.module}/templates/invoke-authorizer-policy.tmpl.json", {
    authorizer_function_arn = local.auth_config.authorizer.function_arn
  })
}


#### API RESOURCES
resource "aws_api_gateway_resource" "s3_proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{proxy+}"

  depends_on = [
    aws_api_gateway_rest_api.api
  ]
}

# resource "aws_api_gateway_resource" "gui_item" {
#   parent_id   = aws_api_gateway_rest_api.api.root_resource_id
#   path_part   = "{item}"
#   rest_api_id = aws_api_gateway_rest_api.api.id

#   depends_on = [
#     aws_api_gateway_rest_api.api
#   ]
# }

resource "aws_api_gateway_resource" "api_item" {
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = var.path
  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_rest_api.api
  ]
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.api_item.id
  path_part   = "{proxy+}"

  depends_on = [
    aws_api_gateway_rest_api.api,
    aws_api_gateway_resource.api_item
  ]
}

resource "aws_api_gateway_resource" "authorizer" {
  count       = local.auth_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = local.auth_config.auth_endpoint_path

  depends_on = [
    aws_api_gateway_rest_api.api
  ]
}

#### API GATEWAY METHODS
resource "aws_api_gateway_method" "root_get" {
  api_key_required = "false"
  authorization    = local.auth_config.enabled ? "CUSTOM" : "NONE"
  authorizer_id    = local.auth_config.enabled ? aws_api_gateway_authorizer.authorizer[0].id : null

  http_method = "GET"

  request_parameters = {
    "method.request.header.Content-Disposition" = "false"
    "method.request.header.Content-Type"        = "false"
  }

  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_rest_api.api,
    aws_api_gateway_resource.s3_proxy,
    aws_api_gateway_resource.api_item
  ]
}

resource "aws_api_gateway_method" "s3_proxy_get" {
  api_key_required = "false"
  authorization    = local.auth_config.enabled ? "CUSTOM" : "NONE"
  authorizer_id    = local.auth_config.enabled ? aws_api_gateway_authorizer.authorizer[0].id : null

  http_method = "GET"

  # request_parameters = {
  #   "method.request.header.Content-Disposition" = "false"
  #   "method.request.header.Content-Type"        = "false"
  #   "method.request.path.item"                  = "true"
  # }

  request_parameters = {
    "method.request.header.Content-Disposition" = "false"
    "method.request.header.Content-Type"        = "false"
    "method.request.path.proxy"                 = true
  }

  resource_id = aws_api_gateway_resource.s3_proxy.id
  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_rest_api.api,
    aws_api_gateway_resource.s3_proxy,
    aws_api_gateway_resource.api_item
  ]
}

# resource "aws_api_gateway_method" "gui_item_options" {
#   api_key_required = "false"
#   authorization    = local.auth_config.enabled ? "CUSTOM" : "NONE"
#   authorizer_id    = local.auth_config.enabled ? aws_api_gateway_authorizer.authorizer[0].id : null

#   http_method = "OPTIONS"

#   resource_id = aws_api_gateway_resource.gui_item.id
#   rest_api_id = aws_api_gateway_rest_api.api.id

#   depends_on = [
#     aws_api_gateway_rest_api.api,
#     aws_api_gateway_resource.gui_item,
#     aws_api_gateway_resource.api_item
#   ]
# }

resource "aws_api_gateway_method" "api_item" {
  api_key_required = "false"
  authorization    = local.auth_config.enabled ? "CUSTOM" : "NONE"
  authorizer_id    = local.auth_config.enabled ? aws_api_gateway_authorizer.authorizer[0].id : null

  http_method = "ANY"

  resource_id = aws_api_gateway_resource.api_item.id
  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_rest_api.api,
    aws_api_gateway_resource.s3_proxy,
    aws_api_gateway_resource.api_item
  ]
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.proxy.id

  http_method = "ANY"

  authorization = local.auth_config.enabled ? "CUSTOM" : "NONE"
  authorizer_id = local.auth_config.enabled ? aws_api_gateway_authorizer.authorizer[0].id : null

  request_parameters = {
    "method.request.path.proxy" = true
  }

  depends_on = [
    aws_api_gateway_rest_api.api,
    aws_api_gateway_resource.proxy
  ]
}

resource "aws_api_gateway_method" "authorizer" {
  count = local.auth_enabled ? 1 : 0

  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.authorizer[0].id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.proxy" = true
  }

  depends_on = [
    aws_api_gateway_rest_api.api,
    aws_api_gateway_resource.authorizer[0]
  ]
}

#### API RESPONSE CONFIGURATION
resource "aws_api_gateway_method_response" "root_get" {
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
    aws_api_gateway_method.root_get
  ]
}

resource "aws_api_gateway_method_response" "s3_proxy_get" {
  http_method = "GET"
  resource_id = aws_api_gateway_resource.s3_proxy.id

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
    aws_api_gateway_method.s3_proxy_get
  ]
}

# TODO: Restore when OPTIONS method is needed
# resource "aws_api_gateway_method_response" "gui_item_options" {
#   http_method = "OPTIONS"
#   resource_id = aws_api_gateway_resource.gui_item.id

#   response_models = {
#     "application/json" = "Empty"
#   }

#   response_parameters = {
#     "method.response.header.Access-Control-Allow-Headers" = "false"
#     "method.response.header.Access-Control-Allow-Methods" = "false"
#     "method.response.header.Access-Control-Allow-Origin"  = "false"
#   }

#   rest_api_id = aws_api_gateway_rest_api.api.id
#   status_code = "200"

#   depends_on = [
#     aws_api_gateway_method.gui_item_options
#   ]
# }

resource "aws_api_gateway_method_response" "api_item" {
  http_method = aws_api_gateway_method.api_item.http_method
  resource_id = aws_api_gateway_resource.api_item.id

  response_models = {
    "application/json" = "Empty"
  }

  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_method.api_item
  ]
}

#### API GATEWAY INTEGRATIONS
resource "aws_api_gateway_integration" "root_get" {
  cache_namespace         = aws_api_gateway_rest_api.api.root_resource_id
  connection_type         = "INTERNET"
  credentials             = aws_iam_role.api_gateway.arn
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
  uri                  = "arn:${var.aws_partition}:apigateway:${var.region}:s3:path/${var.gui_integration.s3_bucket_id}/${var.gui_integration.entrypoint}"

  depends_on = [
    aws_api_gateway_method_response.root_get
  ]
}

resource "aws_api_gateway_integration" "s3_proxy_get" {
  cache_namespace         = aws_api_gateway_resource.s3_proxy.id
  connection_type         = "INTERNET"
  credentials             = aws_iam_role.api_gateway.arn
  http_method             = "GET"
  integration_http_method = "GET"
  passthrough_behavior    = "WHEN_NO_MATCH"

  request_parameters = {
    "integration.request.header.Content-Disposition" = "method.request.header.Content-Disposition"
    "integration.request.header.Content-Type"        = "method.request.header.Content-Type"
    "integration.request.path.proxy"                 = "method.request.path.proxy"
  }

  resource_id          = aws_api_gateway_resource.s3_proxy.id
  rest_api_id          = aws_api_gateway_rest_api.api.id
  timeout_milliseconds = "29000"
  type                 = "AWS"
  uri                  = "arn:${var.aws_partition}:apigateway:${var.region}:s3:path/${var.gui_integration.s3_bucket_id}/{proxy}"

  depends_on = [
    aws_api_gateway_method_response.s3_proxy_get
  ]
}

# resource "aws_api_gateway_integration" "gui_item_options" {
#   cache_namespace      = aws_api_gateway_resource.gui_item.id
#   connection_type      = "INTERNET"
#   http_method          = "OPTIONS"
#   passthrough_behavior = "WHEN_NO_MATCH"

#   request_templates = {
#     "application/json" = jsonencode({
#       "statusCode" = 200
#     })
#   }

#   resource_id          = aws_api_gateway_resource.gui_item.id
#   rest_api_id          = aws_api_gateway_rest_api.api.id
#   timeout_milliseconds = "29000"
#   type                 = "MOCK"

#   depends_on = [
#     aws_api_gateway_method_response.gui_item_options
#   ]
# }

resource "aws_api_gateway_integration" "api_item" {
  cache_namespace = aws_api_gateway_resource.api_item.id
  resource_id     = aws_api_gateway_resource.api_item.id
  rest_api_id     = aws_api_gateway_rest_api.api.id
  http_method     = aws_api_gateway_method.api_item.http_method

  integration_http_method = "POST"
  passthrough_behavior    = "WHEN_NO_MATCH"
  timeout_milliseconds    = "29000"
  type                    = "AWS_PROXY"
  uri                     = local.lambda_invocation_arn

  depends_on = [
    aws_api_gateway_method_response.api_item
  ]
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_method.proxy.resource_id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = local.lambda_invocation_arn

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }

  depends_on = [
    aws_api_gateway_method.proxy
  ]
}

resource "aws_api_gateway_integration" "authorizer" {
  count       = local.auth_enabled ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_method.authorizer[0].resource_id
  http_method = aws_api_gateway_method.authorizer[0].http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = local.authorizer_invocation_arn

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }

  depends_on = [
    aws_api_gateway_method.authorizer
  ]
}

#### API INTEGRATION RESPONSES
resource "aws_api_gateway_integration_response" "root_get" {
  http_method = "GET"
  resource_id = aws_api_gateway_rest_api.api.root_resource_id

  response_parameters = {
    "method.response.header.Content-Disposition" = "integration.response.header.Content-Disposition"
    "method.response.header.Content-Type"        = "integration.response.header.Content-Type"
  }

  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_integration.root_get
  ]
}

resource "aws_api_gateway_integration_response" "s3_proxy_get" {
  http_method = "GET"
  resource_id = aws_api_gateway_resource.s3_proxy.id

  response_parameters = {
    "method.response.header.Content-Disposition" = "integration.response.header.Content-Disposition"
    "method.response.header.Content-Type"        = "integration.response.header.Content-Type"
  }

  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_integration.s3_proxy_get
  ]
}

# resource "aws_api_gateway_integration_response" "gui_item_options" {
#   http_method = "OPTIONS"
#   resource_id = aws_api_gateway_resource.gui_item.id

#   response_parameters = {
#     "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
#     "method.response.header.Access-Control-Allow-Methods" = "'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'"
#     "method.response.header.Access-Control-Allow-Origin"  = "'*'"
#   }

#   rest_api_id = aws_api_gateway_rest_api.api.id
#   status_code = "200"

#   depends_on = [
#     aws_api_gateway_integration.gui_item_options
#   ]
# }

resource "aws_api_gateway_integration_response" "api_item" {
  http_method = "ANY"
  resource_id = aws_api_gateway_resource.api_item.id
  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_integration.api_item
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

resource "aws_api_gateway_integration_response" "authorizer" {
  count = local.auth_enabled ? 1 : 0

  http_method = "GET"
  resource_id = aws_api_gateway_resource.authorizer[0].id
  rest_api_id = aws_api_gateway_rest_api.api.id
  status_code = "200"

  depends_on = [
    aws_api_gateway_integration.authorizer
  ]
}

#### IAM
resource "aws_iam_role" "api_gateway" {
  name = "${var.name}-api_gateway-role"
  path = "/"

  assume_role_policy   = file("${path.module}/templates/assume-role-api-gw-policy.tmpl.json")
  max_session_duration = "3600"

  tags = var.tags
}
