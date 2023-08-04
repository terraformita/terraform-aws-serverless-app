locals {
  api_path = substr(var.backend.path, 1, length(var.backend.path) - 1)

  auth_config    = module.auth_defaults.output
  cognito_config = module.cognito_defaults.output

  auth_endpoint_path = local.auth_enabled ? "${local.auth_config.auth_endpoint_prefix}-${random_id.id.hex}" : ""
  auth_endpoint      = local.auth_enabled ? "https://${var.domain}/${local.auth_endpoint_path}" : ""

  auth_enabled        = !(var.auth_config == null)
  need_cognito_client = (local.auth_enabled && local.auth_config.create_cognito_client)
  cognito_client_id   = local.need_cognito_client ? aws_cognito_user_pool_client.idp_client[0].id : local.cognito_config.client_id

  cognito_url = "https://${local.cognito_config.domain}.auth.${var.region}.amazoncognito.com"
  login_path  = local.auth_enabled ? "login?response_type=code&client_id=${local.cognito_client_id}&redirect_uri=https://${var.domain}/${local.auth_endpoint_path}" : ""
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

module "auth_defaults" {
  source  = "terraformita/defaults/local"
  version = "0.0.6"

  input = var.auth_config
  defaults = {
    cognito   = null
    log_level = "INFO"

    create_cognito_client = true
    auth_endpoint_prefix  = "cognito-idp-response"
  }
}

module "cognito_defaults" {
  source  = "terraformita/defaults/local"
  version = "0.0.6"

  input = local.auth_config.cognito
  defaults = {
    client_id   = ""
    domain      = ""
    secret      = ""
    userpool_id = ""

    refresh_token_validity = 1440 # 24 hours
    access_token_validity  = 60   # 1 hour
    id_token_validity      = 60   # 1 hour

    supported_identity_providers = []
  }
}

module "gui" {
  source = "./gui"

  name       = var.name
  stage_name = var.stage_name

  tags  = var.tags
  files = var.frontend.source

  s3_access_logs_bucket = var.s3_access_logs_bucket
}

module "api" {
  source = "./api"

  name = var.name
  path = local.api_path

  aws_partition  = var.aws_partition == null ? data.aws_partition.current.partition : var.aws_partition
  aws_account_id = var.aws_account_id == null ? data.aws_caller_identity.current.account_id : var.aws_account_id
  stage_name     = var.stage_name
  region         = var.region

  domain          = var.domain
  domain_zone_id  = var.domain_zone_id
  disable_aws_url = var.disable_aws_url
  certificate     = var.certificate
  kms_key_arn     = var.kms_key_arn

  log_retention_days = var.log_retention_days

  gui_integration = {
    s3_bucket_id = module.gui.bucket.id
    entrypoint   = var.frontend.entrypoint
  }

  business_logic = {
    function_arn  = module.backend.lambda_function.arn
    function_name = module.backend.lambda_function.function_name
  }

  binary_media_types = var.binary_media_types

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
    module.auth_lambda,
    module.backend
  ]
}

module "backend" {
  source  = "terraformita/lambda/aws"
  version = "0.1.5"

  stage = var.stage_name
  tags  = var.tags

  # Example lambda function configuration
  function = {
    name        = var.backend.name
    description = try(var.backend.description, "Sample API")

    zip     = var.backend.source
    handler = var.backend.entrypoint
    runtime = var.backend.runtime
    memsize = var.backend.memory_mb
  }

  layer = {
    zip                 = var.backend.modules[0].source
    compatible_runtimes = [var.backend.modules[0].runtime]
  }
}

#### COGNITO USER POOL CLIENT
resource "aws_cognito_user_pool_client" "idp_client" {
  count = local.need_cognito_client ? 1 : 0
  name  = "${var.name}-cognito-idp-client"

  user_pool_id    = local.cognito_config.userpool_id
  generate_secret = true

  explicit_auth_flows = [
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "minutes"
  }

  refresh_token_validity = local.cognito_config.refresh_token_validity
  access_token_validity  = local.cognito_config.access_token_validity
  id_token_validity      = local.cognito_config.id_token_validity

  allowed_oauth_scopes = [
    "phone",
    "email",
    "openid",
    "profile"
  ]

  allowed_oauth_flows_user_pool_client = true

  allowed_oauth_flows  = ["code"]
  callback_urls        = [local.auth_endpoint]
  default_redirect_uri = local.auth_endpoint

  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"
  supported_identity_providers = concat(
    local.cognito_config.supported_identity_providers,
    ["COGNITO"]
  )
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
  function_name = module.backend.lambda_function.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${module.api.execution_arn}/*/*/${local.api_path}"
}

resource "aws_lambda_permission" "business_logic_any_path" {
  count         = local.api_path == "*" ? 0 : 1
  action        = "lambda:InvokeFunction"
  function_name = module.backend.lambda_function.function_name
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
  version = "0.1.5"

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
      CLIENT_ID            = local.need_cognito_client ? aws_cognito_user_pool_client.idp_client[0].id : local.cognito_config.client_id
      CLIENT_SECRET        = local.need_cognito_client ? nonsensitive(aws_cognito_user_pool_client.idp_client[0].client_secret) : local.cognito_config.secret
      COGNITO_DOMAIN       = local.cognito_config.domain
      COGNITO_USER_POOL_ID = local.cognito_config.userpool_id
      LOG_LEVEL            = "INFO"
      REDIRECT_URI         = "/${local.auth_endpoint_path}"
      REGION               = "us-east-1"
      RETURN_URI           = "/${var.frontend.entrypoint}"
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
