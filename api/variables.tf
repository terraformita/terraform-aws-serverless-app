variable "tags" {
  type        = map(any)
  description = "Resource tags to be attached to all resources."
}

variable "domain" {
  type        = string
  default     = null
  description = "Custom domain for the app"
}

variable "domain_zone_id" {
  type        = string
  description = "ID of Route 53 domain zone for the app"
}

variable "certificate" {
  type        = string
  default     = null
  description = "ARN of the certificate for the domain"
}

variable "name" {
  type        = string
  description = "Name of the API"
}

variable "log_retention_days" {
  type        = number
  default     = 7
  description = "Period, in days, to store App access logs in CloudWatch"
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the KMS key used for log data encryption"
}

variable "aws_partition" {
  type        = string
  description = "Name of current AWS partition"
}

variable "aws_account_id" {
  type        = string
  description = "ID of current AWS account"
}

variable "region" {
  type        = string
  description = "AWS Region"
}

variable "gui_integration" {
  type = object({
    s3_bucket_id = string
    entrypoint   = string
  })
  description = "GUI integration: ID of S3 bucket containing frontend files, and entrypoint file (for example: 'index.html')"
}

variable "business_logic" {
  type = object({
    function_name = string
    function_arn  = string
  })
  description = "Business logic reference (corresponding Lambda function ARN)"
}

variable "path" {
  type        = string
  description = "Root path for the API (for exampple: '/api')"
}

variable "logging_config" {
  type = object({
    enable_access_logging    = bool
    enable_execution_logging = bool
    log_full_requests        = bool
    log_retention_days       = optional(number)
  })

  default = {
    enable_access_logging    = true
    enable_execution_logging = false
    log_full_requests        = false
    log_retention_days       = 7
  }
  description = "API logging configuration: logs are sent into standard CloudWatch group."
}

variable "auth_config" {
  type = object({
    enabled            = bool
    auth_endpoint_path = optional(string)
    login_url          = optional(string)
    authorizer = optional(object({
      function_arn = string
      role_arn     = string
      role_id      = string
    }))
  })

  default = {
    enabled = false
  }

  description = "Authentication config for protecting the App and API with Cognito authentication."
}

variable "binary_media_types" {
  type     = list(string)
  nullable = false
  default = [
    "*/*"
  ]
  description = "List of MIME types to be treated as binary for downloading"
}

variable "disable_aws_url" {
  type        = bool
  default     = false
  description = "Disables AWS-provided URL for the App and its API."
}

variable "stage_name" {
  type        = string
  default     = "dev"
  nullable    = false
  description = "API stage name (dev, staging, prod, etc)"
}
