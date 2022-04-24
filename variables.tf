variable "name" {
  type        = string
  description = "Name of the App"
}

variable "domain" {
  type        = string
  default     = null
  description = "Custom domain for the app"
}

variable "domain_zone_id" {
  type        = string
  default     = null
  description = "ID of Route 53 domain zone for the app"
}

variable "certificate" {
  type        = string
  default     = null
  description = "ARN of the certificate for the domain"
}

variable "stage_name" {
  type        = string
  default     = "prod"
  nullable    = false
  description = "Name of the app stage (e.g. dev, staging, prod, etc)"
}

variable "gui" {
  type = object({
    path          = string
    entrypoint    = string
    path_to_files = optional(string)
  })
  default     = null
  description = "GUI layer configuration - API path, default document (entrypoint), path to directory with source files."
}

variable "api" {
  type = object({
    path       = string
    stage_name = optional(string)
    business_logic = object({
      function_arn  = string
      function_name = string
    })
  })
  default     = null
  description = "API layer configuration - API path, ARN and name of the lambda function used as a business logic for the app."
}

variable "s3_access_logs_bucket" {
  type        = string
  default     = null
  description = "Name of the S3 bucket collecting all S3 Bucket Access Logs"
}

variable "tags" {
  type        = map(any)
  description = "Resource tags to be attached to all resources."
}

variable "aws_partition" {
  type        = string
  default     = null
  description = "Name of current AWS partition"
}

variable "aws_account_id" {
  type        = string
  default     = null
  description = "ID of current AWS Account"
}

variable "region" {
  type        = string
  default     = "us-east-1"
  nullable    = false
  description = "AWS Region"
}

variable "log_retention_days" {
  type        = number
  default     = 7
  description = "Period, in days, to store App access logs in CloudWatch"
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "ARN of the KMS key used for log data encryption"
}

variable "enable_access_logging" {
  type        = bool
  default     = true
  description = "Enables access logging at API level. Logs will be sent to the CloudWatch group with name {app-name}-access-logs."
}

variable "enable_execution_logging" {
  type        = bool
  default     = true
  description = "Enables API execution logging. Logs will be sent to the standard API Gateway CloudWatch group."
}

variable "log_full_requests" {
  type        = bool
  default     = false
  description = "Enables or disables full request logging in execution logs. Logs are sent into execution logs group."
}

variable "disable_aws_url" {
  type        = bool
  default     = false
  description = "Disables AWS-provided URL for the App and its API."
}

variable "auth_config" {
  type = object({
    log_level            = optional(string)
    auth_endpoint_prefix = optional(string)

    create_cognito_client = bool

    cognito = optional(object({
      domain      = string
      userpool_id = string
      client_id   = optional(string)
      secret      = optional(string)

      refresh_token_validity = optional(string)
      access_token_validity  = optional(string)
      id_token_validity      = optional(string)

      supported_identity_providers = optional(list(string))
    }))
  })

  default     = null
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

variable "backend" {
  type = object({
    path = string

    name        = string
    description = optional(string)

    source     = string
    entrypoint = string
    runtime    = string
    memory_mb  = number

    modules = list(object({
      source  = string
      runtime = string
    }))
  })
  default     = null
  description = "Backend configuration - API path, stage name, source files, entrypoint, runtime, memory limit (megabytes), list of modules (libraries)."
}

variable "frontend" {
  type = object({
    path        = string
    description = string
    entrypoint  = string
    source      = optional(string)
  })
  default     = null
  description = "Frontend configuration - web path, default document (entrypoint), path to directory with source files."
}
