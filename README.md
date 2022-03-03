
# AWS Serverless App Module for React / Angular / Vue Websites
Terraform module to spin up React/Angular/Vue Serverless App based on AWS API Gateway, with S3 bucket for Client App (GUI) and Lambda function as a Server App (API).

Module supports:
- Custom Domain Name (based on AWS Route 53 or external)
- Web SSL Certificate (based on AWS ACM)
- User Authentication (based on AWS Cognito)

### Features
**Main Features**
- Creates S3 bucket for Client App (GUI)
- Creates AWS API Gateway with ACM SSL Certificate
- Maps S3 bucket to API Root `/`
- Maps provided AWS Lambda function to desired API Path (example: `/api`, or `/backend`, or anything else)

**Optional Features**
- Creates AWS Route 53 Record for Custom Domain
- Protects the whole App with AWS Cognito-based User Authentication
- Turns On API Execution Logs (including request logs) on AWS CloudWatch

**Data Encryption**
- BYOKMS: "Bring Your Own KMS Key" for CloudWatch Log Group logs encryption

### Pre-Requisites
Before using the module:
- Should create ACM Certificate
- (if user auth required) Should create AWS Cognito User Pool and Userpool Client
- (if S3 access logging required) Should create S3 bucket for S3 Access Logging

## Quick Start

Call the `terraformita/serverless-app/aws` module:

```terraform
module "serverless_app" {
  source  = "terraformita/serverless-app/aws"
  version = "Module Version"  # <--- make sure to specify correct version

  name = "Name of Target AWS Environment"

  domain      = "website.example.com"
  certificate = "ARN of AWS ACM Certificate"

  domain-zone-id = "(Optional) ID of AWS Route 53 hosted domain zone"
  s3-logs-bucket = "(Optional, Advanced Feature) ARN of S3 bucket used for S3 Access Logging"
  shared-kms-key = "(Optional, Advanced Feature) ARN of KMS Key to encrypt CloudWatch logs"

  region         = "Target AWS Region (example: us-east-1)"
  aws_partition  = "AWS Partition (example: aws)"
  aws_account_id = "ID of target AWS Account"

  gui = {
    # Required. Client App Configuration
    path          = "Web Access Path. Example: /"
    entrypoint    = "Index Document for Client App. Example: index.html"
    path_to_files = "Optional. Path to files with client app. Example: ${path.module}/files"
  }

  api = {
    # Required. Server App (API, Business Logic) Configuration
    path = "Web Access Path. Example: /api"
    business_logic = {
      function_arn  = "ARN of Lambda Function used as API/Business Logic"
      function_name = "Function Name of Lambda Function used as API/Business Logic"
    }
  }

  auth_config = {
    # Optional. AWS Cognito Configuration for User Authentication
    enabled = true|false # Enables or disables Cognito-based authentication

    cognito = {
      domain = "Name of AWS Cognito Domain"
      userpool_id = "ID of Cognito User Pool"
      client_id = "ID of Userpool Client"
      secret = "Secret of Userpool Client"
    }
  }

  binary_media_types       = ["List", "of", "binary", "MIME", "types", "Defaults", "to", "*/*"]
  enable_access_logging    = true|false # Enables or disables AWS API Gateway Access Logging
  enable_execution_logging = true|false # Enables or disables AWS API Gateway Execution Logging

  tags = {
    # map of tags
  }
}
```

**NB!** Make sure to specify correct module version in the `version` parameter.
