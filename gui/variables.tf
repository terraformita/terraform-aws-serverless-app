variable "name" {
    type = string
    description = "Name of the GUI layer of the app."
}

variable "s3-logs-bucket" {
  type = string
  description = "Name of the bucket into which all S3 access logs being collected in the target AWS environment"
}

variable "files" {
  type = string
  description = "Path to files that will be uploaded to the S3 bucket"
}

variable "tags" {
    type = map
    description = "Tags to set on resources created by the app"
}
