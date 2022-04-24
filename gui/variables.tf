variable "name" {
  type        = string
  description = "Name of the GUI layer of the app."
}

variable "s3_access_logs_bucket" {
  type        = string
  default     = null
  description = "Name and prefix on the S3 bucket collecting all S3 Bucket Access Logs"
}

variable "files" {
  type     = string
  nullable = true
  default  = null

  description = "Path to files that will be uploaded to the S3 bucket"
}

variable "tags" {
  type        = map(any)
  description = "Tags to set on resources created by the app"
}

variable "stage_name" {
  type        = string
  default     = "prod"
  nullable    = false
  description = "Name of the app stage (e.g. dev, staging, prod, etc)"
}
