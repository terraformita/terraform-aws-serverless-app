provider "aws" {
  region = local.region
}

resource "random_pet" "stage_name" {}
resource "random_pet" "function_name" {}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  region    = "us-east-1"
  api_stage = "dev"

  tags = {
    Name = "${random_pet.stage_name.id}-${random_pet.function_name.id}"
  }
}

module "app" {
  source = "../../"

  name = random_pet.stage_name.id

  region         = local.region
  aws_partition  = data.aws_partition.current.partition
  aws_account_id = data.aws_caller_identity.current.account_id

  api = {
    path       = "/api"
    stage_name = local.api_stage
    business_logic = {
      function_arn  = module.backend.lambda_function.arn
      function_name = module.backend.lambda_function.function_name
    }
  }

  gui = {
    path          = "/"
    entrypoint    = "index.html"
    path_to_files = "${path.module}/frontend/public"
  }

  enable_access_logging    = true
  enable_execution_logging = true

  tags = local.tags

  depends_on = [
    module.backend
  ]
}

data "archive_file" "backend" {
  type = "zip"

  source_dir  = "${path.module}/backend/nodejs"
  excludes    = fileset("${path.module}/backend/nodejs", "node_modules/**")
  output_path = "${path.module}/backend/backend.zip"
}

data "archive_file" "layer" {
  type = "zip"

  source_dir  = "${path.module}/backend/nodejs"
  excludes    = ["index.js", "package-lock.json", "package.json"]
  output_path = "${path.module}/backend/layer.zip"
}

module "backend" {
  source = "../../../terraform-aws-lambda"
  # version = "0.1.3"

  stage = random_pet.stage_name.id
  tags  = local.tags

  # Example lambda function configuration
  function = {
    name        = random_pet.function_name.id
    description = "Sample API"

    zip     = "${path.module}/backend/backend1.zip"
    handler = "index.handler"
    runtime = "nodejs12.x"
    memsize = 128
  }

  layer = {
    zip                 = "${path.module}/backend/layer1.zip"
    compatible_runtimes = ["nodejs12.x"]
  }

  depends_on = [
    data.archive_file.backend,
    data.archive_file.layer
  ]
}

output "gui" {
  value = module.app.gui_bucket
}

output "api" {
  value = module.app.api_gateway
}
