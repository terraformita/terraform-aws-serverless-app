locals {
  bucket-name = "${var.name}-gui"
}

#### S3 BUCKET FOR SERVING STATIC GUI CONTENT
module "gui-bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "2.11.1"

  bucket = "${var.name}-gui"
  acl    = "private"

  versioning = {
    enabled = true
  }

  attach_policy = true
  policy        = data.aws_iam_policy_document.gui-bucket.json

  attach_deny_insecure_transport_policy = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  logging = {
    target_bucket = var.s3-logs-bucket
    target_prefix = "uploads/"
  }

  tags = var.tags
}

data "aws_iam_policy_document" "gui-bucket" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      "arn:aws:s3:::${local.bucket-name}",
    ]
  }

  statement {
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "arn:aws:s3:::${local.bucket-name}/*",
    ]
  }
}

resource "random_id" "trigger" {
  byte_length = 8

  keepers = {
    uuid = uuid()
  }
}

resource "null_resource" "deploy" {
  provisioner "local-exec" {
    command = <<EOF
    aws s3 sync --quiet --delete --exclude ".git/*" \
      ${var.files} s3://${module.gui-bucket.s3_bucket_id}/
    EOF
  }

  triggers = {
    update = element(concat(random_id.trigger.*.hex, []), 0)
  }

  depends_on = [
    module.gui-bucket
  ]
}
