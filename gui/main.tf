locals {
  bucket-name = "${var.name}-gui"
}

#### S3 BUCKET FOR SERVING STATIC GUI CONTENT
resource "aws_s3_bucket" "gui" {
  bucket        = "${var.name}-gui"
  acl           = "private"
  force_destroy = true

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  logging {
    target_bucket = var.s3-logs-bucket
    target_prefix = "${var.name}-gui/"
  }

  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "gui" {
  bucket = aws_s3_bucket.gui.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "gui" {
  bucket = aws_s3_bucket.gui.id
  policy = data.aws_iam_policy_document.gui-bucket.json
}

data "aws_iam_policy_document" "gui-bucket" {
  statement {
    sid = "AllowAPIGWListBucket"
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }

    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]

    resources = [
      "arn:aws:s3:::${local.bucket-name}",
    ]
  }

  statement {
    sid = "AllowAPIGWGetObject"
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }

    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]

    resources = [
      "arn:aws:s3:::${local.bucket-name}/*",
    ]
  }

  statement {
    sid = "DenyOutdatedTLS"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "s3:*"
    ]

    effect = "Allow"

    resources = [
      "arn:aws:s3:::${local.bucket-name}",
      "arn:aws:s3:::${local.bucket-name}/*",
    ]

    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"

      values = [
        "1.2"
      ]
    }
  }

  statement {
    sid = "DenyInsecureConnections"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    effect = "Deny"
    actions = [
      "s3:*"
    ]

    resources = [
      "arn:aws:s3:::${local.bucket-name}",
      "arn:aws:s3:::${local.bucket-name}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"

      values = [
        "false"
      ]
    }
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
      ${var.files} s3://${aws_s3_bucket.gui.id}/
    EOF
  }

  triggers = {
    update = element(concat(random_id.trigger.*.hex, []), 0)
  }

  depends_on = [
    aws_s3_bucket.gui
  ]
}
