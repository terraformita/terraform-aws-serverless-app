import os
import jwt
import json
import base64
import requests
import random
from http.cookies import SimpleCookie

cognito_domain = os.environ["COGNITO_DOMAIN"]
userpool_id = os.environ["COGNITO_USER_POOL_ID"]
region = os.environ["REGION"]

cognito_uri = f"https://{cognito_domain}.auth.{region}.amazoncognito.com"
keys_url = f"https://cognito-idp.{region}.amazonaws.com/{userpool_id}/.well-known/jwks.json"

# instead of re-downloading the public keys every time
# we download them only on cold start
# https://aws.amazon.com/blogs/compute/container-reuse-in-lambda/
with requests.get(keys_url) as f:
  response = f.text
keys = json.loads(response)['keys']

client_id = os.environ["CLIENT_ID"]
client_secret = os.environ["CLIENT_SECRET"]
base_uri = os.environ["BASE_URI"]
redirect_uri = base_uri + os.environ["REDIRECT_URI"]
return_uri = base_uri + os.environ["RETURN_URI"]

log_level = os.environ.get('LOG_LEVEL', "INFO")
debug = (log_level == 'DEBUG')

def lambda_handler(event, context):
    log_debug(event)
    log_debug(json.dumps(keys))

    if event is None:
        return {
            'statusCode': 400,
            'body': error_json('Invalid request: request is empty.')
        }

    if ('queryStringParameters' in event) and ('code' in event['queryStringParameters']):
        code = event['queryStringParameters']['code']
        return handle_login_request(code)
    
    return handle_authenticated_request(event)

def handle_authenticated_request(event):
    log_debug('Handling authenticated request')
    username = "sub"
    
    if not 'methodArn' in event:
        log_debug('Method ARN is not present in the request')
        log_debug('Request will be denied')
        log_debug(event)
        return generate_policy(username, "Deny", "unknown/unknown")
    
    try:
        cookie = SimpleCookie()
        cookie.load(event["headers"]["cookie"])
        log_debug(f"Cookie: {cookie}")
        
        token = cookie["Authorization"].value
        log_debug(f"Token from cookie: {token}")
    except Exception as e:
        log_error("Problem retrieving Token Cookie from request", e)
        return generate_policy(username, "Deny", event["methodArn"])

    try:
        payload = decode_token(token)
        username = payload['sub']
    except jwt.ExpiredSignatureError:
        log_error("JWT token is expired")
        return generate_policy(username, "Deny", event["methodArn"])
    
    return generate_policy(username, "Allow", event["methodArn"])

def generate_policy(principal_id, effect, method_arn):
    auth_response = {}
    auth_response["principalId"] = principal_id

    base = method_arn.split("/")[0]
    stage = method_arn.split("/")[1]
    log_debug(f"Parsed base: {base}")
    log_debug(f"Parsed stage: {stage}")
    
    arn = base + "/" + stage + "/*/*"
    log_debug(f"Constructed arn: {arn}")
    
    if effect and method_arn:
        policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "APIMethodInvocationAuthorization",
                    "Action": "execute-api:Invoke",
                    "Effect": effect,
                    "Resource": arn,
                }
            ],
        }
        auth_response["policyDocument"] = policy_document
    return auth_response

def handle_login_request(code):
    log_debug('Handling login request')
    result = {
        'statusCode': 200,
        'body': ''
    }

    token_url=f"{cognito_uri}/oauth2/token"
    message = bytes(f"{client_id}:{client_secret}",'utf-8')
    secret_hash = base64.b64encode(message).decode()
    payload = {
        "grant_type": 'authorization_code',
        "client_id": client_id,
        "code": code,
        "redirect_uri": redirect_uri
    }
    headers = {"Content-Type": "application/x-www-form-urlencoded",
                "Authorization": f"Basic {secret_hash}"}

    resp = requests.post(token_url, params=payload, headers=headers)
    log_debug(f"Response from cognito: {resp.status_code}: {resp.text}")

    if resp.status_code == 200:
        tokens = json.loads(resp.text)
        log_debug(f"Retrieved access token: {tokens['access_token']}")
        result['statusCode'] = 302
        result['headers'] = {
            'Location': return_uri
        }
        result['multiValueHeaders'] = {
            'Set-Cookie': [
                f"Authorization={tokens['access_token']}", 
                f"ID_Token={tokens['id_token']}",
            ]
        }
        return result

    result['statusCode'] = resp.status_code
    result['body'] = resp.text

    return result

def decode_token(token):
    log_debug("Started decode_token")

    header = jwt.get_unverified_header(token)
    log_debug(f"Token unverified header: {header}")

    kid = header['kid']
    alg = header['alg']
    
    public_key = None

    for jwk in keys:
        key_id = jwk['kid']
        
        if key_id == kid:
            public_key = jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(jwk))
            log_debug(f"Constructed public key: {public_key}")

    if public_key is None:
        raise Exception('Public key was not found in JWKS Collection')
    
    payload = jwt.decode(token, key=public_key, algorithms=[alg])
    log_debug(f"JWT token payload: {payload}")
    
    return payload

def log_error(explanation, e=None):
    underlying_error = ""
    if not (e is None):
        underlying_error = f" Underlying Error: {str(e)}"

    log("ERROR", f"{explanation}{underlying_error}")

def log(level, stuff):
    if level == "NONE" or (level == "DEBUG" and (debug is False)):
        return
    print(f"{level}: {stuff}")

def log_debug(stuff):
    log('DEBUG', stuff)

def error_json(text):
    return json.dumps({'error': text})
