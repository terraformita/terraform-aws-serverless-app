# AWS Serverless App Module for React / Angular / Vue Websites
Terraform module to spin up React/Angular/Vue Serverless App based on AWS API Gateway, with S3 bucket for Client App (GUI) and Lambda function as a Backend App (API).

Module Supports:
- Custom Domain Name (based on AWS Route 53 or external)
- Web SSL Certificate (based on AWS ACM)
- User Authentication (based on AWS Cognito)

## Features
### Main Features
- Creates S3 bucket for Client App (GUI)
- Creates AWS API Gateway with ACM SSL Certificate
- Maps S3 bucket to API Root `/`
- Maps provided AWS Lambda function to desired API Path (example: `/api`, or `/backend`, or anything else)

### Optional Features
- Creates AWS Route 53 Record for Custom Domain
- Protects the whole App with AWS Cognito-based User Authentication
- Turns On API Execution Logs (including request logs) on AWS CloudWatch

### Data Encryption
- BYOKMS: "Bring Your Own KMS Key" for CloudWatch Log Group logs encryption

## Infrastructure
![Serverless App Module Infrastructure](https://user-images.githubusercontent.com/1422584/156475917-9bc87d9d-d656-480a-959e-9da2836568e3.png)

## OPTIONAL Pre-Requisites
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

  name        = "Name of the App (example: React App)"
  stage_name  = "(Optional) Name of the deployment stage (default: 'dev')"

  domain      = "(Optional) Custom domain, such as: website.example.com"
  certificate = "(Optional) ARN of AWS ACM (SSL) Certificate"

  domain_zone_id        = "(Optional) ID of AWS Route 53 hosted domain zone"
  s3_access_logs_bucket = "(Optional, Advanced Feature) ARN of S3 bucket used for S3 Access Logging"

  kms_key_arn        = "(Optional, Advanced Feature) ARN of KMS Key to encrypt CloudWatch logs"
  log_retention_days = "(Optional, Advanced Feature) Period, in days, to store App access logs in CloudWatch. Defaults to 7"

  region         = "(Optional) Target AWS Region (default: us-east-1)"
  aws_partition  = "(Optional) AWS Partition (default: current partition)"
  aws_account_id = "(Optional) ID of target AWS Account (default: current Account ID)"

  frontend = {
    Required. Frontend configuration.
    path = "Web Access Path. Example: /"

    description = "(Optional) App description, for example: 'React App Frontend'"
    entrypoint  = "Index Document for Client App. Example: index.html"
    source      = "(Optional) Path to directory with frontend files. Example: ${path.module}/frontend"
  }

  backend = {
    # Required. App backend configuration. Will be turned into AWS Lambda function.    
    path = "Web Access Path. Example: /api"

    name        = "Machine-readable name of the backend (example: react-app-backend)"
    description = "(Optional) Description of the backend (example: React App Backend)"

    source     = "Path to directory with backend files. Example: ${path.module}/backend"
    entrypoint = "Combination of main file name of the backend and its entry function (example: index.handler, where 'index' refers to 'index.js' and 'handler' is a function declared within 'index.js')."
    runtime    = "AWS-supported Lambda function runtime used to run backend"
    memory_mb  = "AWS-supported number of megabytes of memory allocated for the backend Lambda function"

    modules = [
      # Optional. Required if backend uses external modules (i.e. "node_modules" in case of nodejs)
      {
        source  = "Path to directory with modules (libraries) of the backend. Example: ${path.module}/backend"
        runtime = "AWS-supported Lambda function runtime used to run backend"
      }
    ]
  }

  auth_config = {
    # Optional. AWS Cognito Configuration for User Authentication
    enabled   = true|false # Enables or disables Cognito-based authentication
    log_level = "API Logging Level (INFO or ERROR). Defaults to INFO"

    auth_endpoint_prefix = "(Advanced Feature). URL Prefix for OAuth callback endpoint. Defaults to: cognito-idp-response"

    create_cognito_client = true|false # Indicates if module should create Cognito Client for user authentication. Defaults to true.

    cognito = {
      domain      = "Name of AWS Cognito Domain"
      userpool_id = "ID of Cognito User Pool"
      client_id   = "Optional. ID of Existing Cognito Userpool Client"
      secret      = "Optional. Secret of Existing Userpool Client"

      refresh_token_validity = "Optional. Refresh token validity in MINUTES. Defaults to 1440 (24 hrs)"
      access_token_validity  = "Optional. Access token validity in MINUTES. Defaults to 60 (1 hr)"
      id_token_validity      = "Optional. ID token validity in MINUTES. Defaults to 60 (1 hr)"

      supported_identity_providers = [ "List", "of", "identity", "providers", "supported", "by", "the", "client" ]
    }
  }

  binary_media_types       = ["List", "of", "binary", "MIME", "types", "Defaults", "to", "*/*"]
  enable_access_logging    = true|false # Enables AWS API Gateway Access Logging. Defaults to true.
  enable_execution_logging = true|false # Enables AWS API Gateway Execution Logging. Defaults to true.
  log_full_requests        = true|false # Enables logging of full requests (payloads). Defaults to false.

  disable_aws_url = true|false # Indicates if AWS-provided API Gateway URL should be disabled. Defaults to false

  tags = {
    # map of tags
  }
}
```

**NB!** Make sure to specify correct module version in the `version` parameter.

## Post-Deployment Steps

Usually no post-deployment steps are required. However, if you chose to use existing AWS Cognito Userpool Client instead of letting the module to create the new one, the below post-deployment steps are needed to make everything work.

### When These Steps Needed

- You turn on User Authentication via Cognito
- You chose to not let the module create Cognito Client

### What Needs To Be Done
- Visit AWS API Gateway console
- Find the API created by the module
- Find the Authentication API Endpoint (`api_gateway.auth_endpoint` output variable)
- Copy the Authentication API Endpoint path to Clipboard

- Open AWS Cognito Console
- Locate your App Client used for User Authentication
- Change "Redirect URL" to copied API Endpoint
