terraform {
  required_providers {
    aws = {
      version = "3.74.2"
      source  = "hashicorp/aws"
    }
  }

  experiments = [module_variable_optional_attrs]
}

locals {
  api_path           = substr(var.api.path, 1, length(var.api.path) - 1)
  auth_config        = module.auth_defaults.output
  auth_endpoint_path = "${local.auth_config.auth_endpoint_prefix}-${random_id.id.hex}"

  auth_config_present = !(var.auth_config == null)
  auth_enabled        = local.auth_config_present ? var.auth_config.enabled : false

  cognito_url = "https://${local.auth_config.cognito.domain}.auth.${var.region}.amazoncognito.com"
  login_path  = "login?response_type=code&client_id=${local.auth_config.cognito.client_id}&redirect_uri=https://${var.domain}/${local.auth_endpoint_path}"
}

module "auth_defaults" {
  source  = "terraformita/defaults/local"
  version = "0.0.6"

  input = var.auth_config
  defaults = {
    enabled              = false
    log_level            = "INFO"
    auth_endpoint_prefix = "cognito-idp-response"

    cognito = {
      domain      = ""
      userpool_id = ""
      client_id   = ""
      secret      = ""
    }
  }
}

module "gui" {
  source = "./gui"

  name  = var.name
  tags  = var.tags
  files = var.gui.path_to_files

  s3_access_logs_bucket = var.s3_access_logs_bucket
}

module "api" {
  source = "./api"

  name = var.name
  path = local.api_path

  aws_partition  = var.aws_partition
  aws_account_id = var.aws_account_id
  region         = var.region

  domain         = var.domain
  domain_zone_id = var.domain_zone_id
  certificate    = var.certificate
  kms_key_arn    = var.kms_key_arn

  log_retention_days = var.log_retention_days

  gui_integration = {
    s3_bucket_id = module.gui.bucket.id
    entrypoint   = var.gui.entrypoint
  }

  business_logic = var.api.business_logic
  auth_config = {
    enabled            = local.auth_enabled
    login_url          = "${local.cognito_url}/${local.login_path}"
    auth_endpoint_path = local.auth_endpoint_path

    authorizer = local.auth_enabled ? {
      function_arn = module.auth_lambda[0].lambda_function.arn
      role_arn     = module.auth_lambda[0].lambda_function.role_arn
      role_id      = module.auth_lambda[0].lambda_function.role_id
    } : null
  }

  logging_config = {
    enable_access_logging    = var.enable_access_logging
    enable_execution_logging = var.enable_execution_logging
    log_full_requests        = var.log_full_requests
  }

  tags = var.tags

  depends_on = [
    module.auth_lambda
  ]
}

#### API ACCESS TO GUI BUCKET
resource "aws_iam_policy" "gui_bucket" {
  name   = "${var.name}-gui-bucket-access"
  policy = data.aws_iam_policy_document.gui_bucket.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "gui_bucket" {
  role       = module.api.user_role.name
  policy_arn = aws_iam_policy.gui_bucket.arn
}

data "aws_iam_policy_document" "gui_bucket" {
  statement {
    actions = [
      "s3:ListBucket"
    ]

    resources = [
      module.gui.bucket.arn
    ]
  }

  statement {
    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${module.gui.bucket.arn}/*"
    ]
  }
}

#### BUSINESS LOGIC CALLING PERMISSIONS
resource "aws_lambda_permission" "business_logic_root" {
  action        = "lambda:InvokeFunction"
  function_name = var.api.business_logic.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${module.api.execution_arn}/*/*/${local.api_path}"
}

resource "aws_lambda_permission" "business_logic_any_path" {
  count         = local.api_path == "*" ? 0 : 1
  action        = "lambda:InvokeFunction"
  function_name = var.api.business_logic.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${module.api.execution_arn}/*/*/${local.api_path}/*"
}

resource "aws_lambda_permission" "auth" {
  count         = local.auth_enabled ? 1 : 0
  action        = "lambda:InvokeFunction"
  function_name = module.auth_lambda[0].lambda_function.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${module.api.execution_arn}/*/GET/${local.auth_endpoint_path}"
}

resource "aws_lambda_permission" "authorizer" {
  count         = local.auth_enabled ? 1 : 0
  action        = "lambda:InvokeFunction"
  function_name = module.auth_lambda[0].lambda_function.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${module.api.execution_arn}/authorizers/${module.api.authorizer_id}"
}

#### AUTHENTICATION LAMBDA
resource "random_id" "id" {
  byte_length = 8
}

data "archive_file" "auth_lambda" {
  type = "zip"

  source_dir  = "${path.module}/lambda/auth/code"
  output_path = "${path.module}/lambda/auth/lambda_handler.py.zip"
}

module "auth_lambda" {
  count = local.auth_enabled ? 1 : 0

  source  = "terraformita/lambda/aws"
  version = "0.1.3"

  stage = var.name
  tags  = var.tags

  function = {
    name        = "cognito-authorizer"
    description = "Lambda authorizer for ${var.name} app, that performs user authentication and authorization via Amazon Cognito."

    zip     = "${path.module}/lambda/auth/lambda_handler.py.zip"
    handler = "lambda_handler.lambda_handler"
    runtime = "python3.7"
    memsize = "256"

    env = {
      BASE_URI             = "https://${var.domain}"
      CLIENT_ID            = var.auth_config.cognito.client_id
      CLIENT_SECRET        = var.auth_config.cognito.secret
      COGNITO_DOMAIN       = var.auth_config.cognito.domain
      COGNITO_USER_POOL_ID = var.auth_config.cognito.userpool_id
      LOG_LEVEL            = "INFO"
      REDIRECT_URI         = "/${local.auth_endpoint_path}"
      REGION               = "us-east-1"
      RETURN_URI           = "/${var.gui.entrypoint}"
    }

    policies = {
    }
  }

  layer = {
    zip                 = "${path.module}/lambda/auth/sdk-layer.zip"
    compatible_runtimes = ["python3.7"]
  }

  depends_on = [
    data.archive_file.auth_lambda
  ]
}