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

module "api" {
  source = "./api"

  name = var.name
  path = local.api-path-part

  aws-partition = var.aws-partition
  aws-account   = var.aws-account
  region        = var.region

  domain         = var.domain
  domain-zone-id = var.domain-zone-id
  certificate    = var.certificate
  shared-kms-key = var.shared-kms-key

  log-retention-days = var.log-retention-days

  gui-integration = {
    s3-bucket-id = module.gui.out.s3-bucket-id
    entrypoint   = var.gui.entrypoint
  }

  business-logic = {
    resource-arn = var.api.business-logic.resource.arn
  }

  enable-access-logging    = var.enable-access-logging
  enable-execution-logging = var.enable-execution-logging
  log-full-requests        = var.log-full-requests

  tags = var.tags
}

#### API ACCESS TO GUI BUCKET
resource "aws_iam_policy" "gui-bucket" {
  name   = "${var.name}-gui-bucket-access"
  policy = data.aws_iam_policy_document.gui-bucket.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "gui-bucket" {
  role       = module.api.user-role.name
  policy_arn = aws_iam_policy.gui-bucket.arn
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
resource "aws_lambda_permission" "business-logic-main" {
  action        = "lambda:InvokeFunction"
  function_name = var.api.business-logic.resource.function-name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${module.api.execution-arn}/*/*/${local.api-path-part}"
}

resource "aws_lambda_permission" "business-logic-any" {
  count         = local.api-path-part == "*" ? 0 : 1
  action        = "lambda:InvokeFunction"
  function_name = var.api.business-logic.resource.function-name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${module.api.execution-arn}/*/*/${local.api-path-part}/*"
}
