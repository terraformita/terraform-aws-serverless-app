
variable "tags" {
  type        = map(any)
  description = "Resource tags to be attached to all resources."
}

variable "domain" {
  type        = string
  default     = null
  description = "Custom domain for the app"
}

variable "domain-zone-id" {
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

variable "log-retention-days" {
  type        = number
  default     = 7
  description = "Period, in days, to store App access logs in CloudWatch"
}

variable "shared-kms-key" {
    type = string
    description = "ARN of the KMS key used for log data encryption"
}

variable "aws-partition" {
  type        = string
  description = "Name of current AWS partition"
}

variable "aws-account" {
  type        = string
  description = "ID of current AWS account"
}

variable "region" {
  type        = string
  description = "AWS Region"
}

variable "gui-integration" {
    type = object({
        s3-bucket-id = string
        entrypoint = string
    })
    description = "GUI integration: ID of S3 bucket containing frontend files, and entrypoint file (for example: 'index.html')"
}

variable "business-logic" {
    type = object({
        resource-arn = string
    })
    description = "Business logic reference (corresponding Lambda function ARN)"
}

variable "path" {
    type = string
    description = "Root path for the API (for exampple: '/api')"
}

variable "enable-access-logging" {
    type = bool
    default = true
    description = "Enables or disables API access logging. Logs are sent into standard CloudWatch group."
}

variable "enable-execution-logging" {
    type = bool
    default = false
    description = "Enables or disables API execution logging. Logs are sent into standard CloudWatch group."
}

variable "log-full-requests" {
    type = bool
    default = false
    description = "Enables or disables full request logging in execution logs. Logs are sent into execution logs group."
}
