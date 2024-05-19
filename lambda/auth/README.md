# Build Lambda Layer

**IMPORTANT**. In order for Lambda to run successfully, make sure to build all Python modules on Amazon Linux 2 box.

## Run AmazonLinux2 Container

- `docker pull amazonlinux` - pull amazonlinux image from [Docker Hub](https://hub.docker.com/_/amazonlinux)
- `docker run -v {path_to_wazuh_lambda_folder}:/lambda --rm -it amazonlinux bash` - run amazonlinux image and mount the `path to wazuh_lambda_folder` as `/lambda` in the container. **NOTE** For M1 add `--platform linux/amd64` to the `docker run` command
- Install necessary pre-requisites (specifically, [Python 3.8](https://techviewleo.com/how-to-install-python-on-amazon-linux/)):

```bash
yum install -y python
yum install -y gcc
amazon-linux-extras | grep -i python
amazon-linux-extras enable python3.8
yum install -y python38 python38-devel
```

## Build Lambda SDK Layer

Execute the following commands inside the running container:

- `cd /lambda` - chdir to the mounted lambda directory
- `python3 -m ensurepip --upgrade` <- to install pip3
- `python3 -m venv venv` <- to enable virtual environment
- `source venv/bin/activate` <- to activate virtual environment
- `pip3 install pipreqs`
- `pipreqs .` <- to build "requirements.txt" file
- `pip3 install -r requirements.txt --platform manylinux2014_aarch64 --implementation cp --only-binary=:all: --upgrade --target ./python` <- to download required modules into `<dst_folder>`
- `pip3 install --platform manylinux2014_aarch64 --target=./python --implementation cp --only-binary=:all: --upgrade cryptography`
- `pip3 install --platform manylinux2014_aarch64 --target=./python --implementation cp --only-binary=:all: --upgrade jwt`
- `pip3 install --platform manylinux2014_aarch64 --target=./python --implementation cp --only-binary=:all: --upgrade PyJWT`
- `pip3 install --platform manylinux2014_aarch64 --target=./python --implementation cp --only-binary=:all: --upgrade cffi`
- `pip3 install --platform manylinux2014_aarch64 --target=./python --implementation cp --only-binary=:all: --upgrade pyjwt["crypto"]` <- to download `pyjwt`'s cryptographics module needed for proper working of JWT token decryption.
- `pip3 install requests-aws4auth --upgrade --target ./python` <- to download `requests-aws4auth` module needed for signing HTTP requests
- `pip3 install requests --upgrade --target ./python` <- to download `requests` module needed for proper working of the Elasticsearch module.
- `zip -r sdk-layer.zip ./python/` <- to create ZIP archive with the lambda layer
- `deactivate` <- to exit virtual environment



```
pip3.8 install     --platform manylinux2014_aarch64     --target=./python     --implementation cp    --only-binary=:all: --upgrade
```
