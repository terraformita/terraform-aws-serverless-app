# Simple React App Deployment to AWS Example

## Overview

This example deploys to AWS a simple React app with React Frontend in `frontend` directory, and Nodejs backend (API) in `backend` directory.

The deployment consists of 2 steps:
- Pre-requisites (compile frontend and backend)
- Deployment (deploy to AWS)

Both steps are detailed below.

## Pre-Requisites

### Compile Frontend

Run the following commands to initialize and compile frontend.

- Initialize frontend
```
cd frontend
npm init -y
```

- Install required packages
```
npm install --save-dev babel-cli
npm install babel-preset-react-app@3
```

- Compile React App
```
npx babel src --out-dir public/js --presets react-app/prod
```

### Compile Backend

- Initialize backend
```
cd backend
npm init -y
```

- Install required packages: `express` and `serverless-http`
```
npm install --save express
npm install --save serverless-http
```

## Deployment

- Run `terraform apply` to deploy application to AWS. The output will look like this:

```
deployment = {
  "auth_endpoint" = ""
  "aws_url" = "https://nqav0yhr9b.execute-api.us-east-1.amazonaws.com/dev"
  "custom_domain_url" = ""
  "execution_arn" = "arn:aws:execute-api:us-east-1:990617134998:nqav0yhr9b"
  "stage" = "dev"
  "user_role_arn" = "arn:aws:iam::990617134998:role/adapted-gnu-api_gateway-role"
}
frontend_storage = {
  "arn" = "arn:aws:s3:::adapted-gnu-dev-gui"
  "id" = "adapted-gnu-dev-gui"
}
```

- The "aws_url" field from the output is an URL where the app is deployed: `https://nqav0yhr9b.execute-api.us-east-1.amazonaws.com/dev` from the above, where `/dev` is a "stage" (e.g. "dev", "staging", "prod", etc).

## Enjoy the App

Open "aws_url" in your web browser and see the app in action.
