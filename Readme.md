# KONG-AWS-REQUEST-SIGNING

[![Build](https://github.com/LEGO/kong-aws-request-signing/actions/workflows/build.yml/badge.svg)](https://github.com/LEGO/kong-aws-request-signing/actions/workflows/build.yml)

## About

This plugin will sign a request with AWS SIGV4 and temporary credentials from `sts.amazonaws.com` requested using an OAuth token.

It enables the secure use of AWS [Lambda URLs](https://aws.amazon.com/blogs/aws/announcing-aws-lambda-function-urls-built-in-https-endpoints-for-single-function-microservices/) being registered as "Host" in a Kong service.

At the same time it drives down cost and complexity by excluding the AWS API Gateway and allowing to use AWS Lambdas directly.

The required AWS setup to make the plugin work with your Lambda HTTPS endpoint is described below.

Note that this plugin cannot be used in combination with Kong [upstreams](https://docs.konghq.com/gateway/latest/get-started/load-balancing/).

## Plugin configuration parameters

```lua
aws_assume_role_arn - ARN of the IAM role that the plugin will try to assume
type = "string"
required = true

aws_assume_role_name - Name of the role above.
type = "string"
required = true

aws_region - AWS region where your Lambda is deployed to
type = "string"
required = true

aws_service - AWS Service you are trying to access (lambda and s3 were tested)
type = "string"
required = true

override_target_host - To be used when deploying multiple lambdas on a single Kong service (because lambdas have differennt URLs)
type = "string"
required = false

override_target_port - To be used when deploying a Lambda on a Kong service that listens on a port other than `443`
type = "number"
required = false

override_target_protocol - To be used when deploying a Lambda on a Kong service that has a protocol different than `https`
type = "string"
one_of = "http", "https"
required = false

return_aws_sts_error - Whether to return the AWS STS response status and body when credentials fetching failed.
type = "boolean"
default = false
required = false

sign_query - Controls if the signature will be sent in the header or in the query. By default, header is used, if enabled will sign the query.
type = "boolean"
required = true
default = false

preserve_auth_header - Controls if the bearer token will be passed to the upstream
type = "boolean"
required = true
default = true

preserve_auth_header_key - The header key where the bearer token will be saved and passed to the upstream. works only if 'preserve_auth_header' parameter above is set to true.
type = "string"
required = true
default = "x-authorization"
```

## Using multiple Lambdas with the same Kong Service

The plugin can be enabled on a per-service and per-route basis. When enabled for a route, the plugin will direct traffic to the service's upstream Lambda target, unless ***`override_target_host`*** is specified.

If multiple Lambdas are needed for a single service, each route must have the plugin enabled with ***`override_target_host`*** configured, so that requests are correctly routed to the right Lambda.

If ***`override_target_host`*** is not specified and multiple Lambdas are used in the service, all routes will be served by the same service-level host.

You can also set the service protocol and host to something like `http://example.com` and then use `override_target_protocol` and `override_target_host` to changed it on the path level.

## Installing the plugin

There are two things necessary to make a custom plugin work in Kong:

1. Load the plugin files.

The easiest way to install the plugin is using `luarocks`.

```sh
luarocks install https://github.com/LEGO/kong-aws-request-signing/raw/main/rocks/kong-aws-request-signing-1.0.5-3.all.rock
```

You can substitute `1.0.0-3` in the command above with any other version you want to install.

If running Kong using the Helm chart, you will need to create a config map with the plugin files and mount it to `/opt/kong/plugins/aws-request-signing`. You can read more about this on [Kong's website.](https://docs.konghq.com/kubernetes-ingress-controller/latest/guides/setting-up-custom-plugins/)

2. Specify that you want to use the plugin by modifying the plugins property in the Kong configuration.

Add the custom plugin’s name to the list of plugins in your Kong configuration:

```conf
plugins = bundled, aws-request-signing
```

If you are using the Kong helm chart, create a configMap with the plugin files and add it to your `values.yaml` file:

```yaml
# values.yaml
plugins:
  configMaps:
  - name: kong-plugin-aws-request-signing
    pluginName: aws-request-signing
```

## Signing requests containing a body

In case of requests containing a body, the plugin is highly reliant on the nginx configuration, because it needs to access the body to sign it.
The behavior is controlled by the following Kong configuration parameters:

```text
nginx_http_client_max_body_size
nginx_http_client_body_buffer_size
```

[Kong docs reference.](https://docs.konghq.com/gateway/latest/reference/configuration/#nginx_http_client_body_buffer_size)

The default value for max body size is `0`, which means unlimited, so consider setting the `nginx_http_client_body_buffer_size` as high as you consider reasonable, as requests containing a bigger body, will fail.

## AWS Setup required

1. You have a [Lambda function](https://eu-west-1.console.aws.amazon.com/lambda/home?region=eu-west-1#) deployed with `Function URL` enabled and Auth type : `AWS_IAM` or you have an S3 bucket with public access disabled.

<details>
<summary>Show image</summary>
<br>

![Lambda example](https://user-images.githubusercontent.com/29011940/183050407-553a5ea9-f746-4baa-8b41-3a88b852ec4b.png)
</details>

2. Your OpenID Connect provider is added to [AWS IAM](https://us-east-1.console.aws.amazon.com/iamv2/home?region=us-east-1#/identity_providers)
3. You have a role with  `arn:aws:iam::aws:policy/AWSLambda_FullAccess` and/or `arn:aws:iam::aws:policy/AmazonS3FullAccess`  permission (or any other permission that grants access to your desired AWS service ) and the trust relationship below:

<details>
<summary>Show JSON</summary>
<br>

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "${arn_of_the_open_id_connect_provider_step_1}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${the_open_id_connect_provider_step_1}:aud": "${audience_of_the_lambda_given_by_your_open_id_provider}"
                }
            }
        }
    ]
}
```

</details>

So if your provider is `https://sts.windows.net/organization.onmicrosoft.com/` and your app identity is `app_identity_1`, the trust relationship above will look like:

<details>
<summary>Show JSON</summary>
<br>

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::300000000000:oidc-provider/sts.windows.net/organization.onmicrosoft.com/"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "sts.windows.net/organization.onmicrosoft.com/:aud": "app_identity_1"
                }
            }
        }
    ]
}
```

</details>

## About the code and differences from [Kong Lambda Plugin](https://github.com/Kong/kong/blob/master/kong/plugins/aws-lambda)

Some of the code was reused from [Kong Lambda Plugin](https://github.com/Kong/kong/blob/master/kong/plugins/aws-lambda) specifically the [SIGV4 creation](https://github.com/Kong/kong/blob/master/kong/plugins/aws-lambda/v4.lua) code and some parts for [getting the temporary credentials from AWS STS](https://github.com/Kong/kong/blob/master/kong/plugins/aws-lambda/iam-sts-credentials.lua). There are some considerable differences that will be outlined below:

1. Unlike Kong-Lambda This plugin does not perform the Lambda invocation. But only signs the request coming from the consumer which Kong then forwards to the upstream that it is configured in the service that the plugin is bound to.
2. The plugin works only with temporary credentials that are fetched from `sts.amazonaws.com` using [AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html#API_AssumeRoleWithWebIdentity_RequestParameters), this requires some configuration in AWS which can be found above.
3. This plugin has a low priority and is compatible with the rest of Kong plugins because as mentioned above, it only performs SIGV4 on the request and then appends the necessary headers to be authorized in AWS.

## Open Source Attribution

* [Kong](https://github.com/Kong/kong) : [Apache 2.0 License](https://github.com/Kong/kong/blob/master/LICENSE)
* [lua-resty-string](https://github.com/openresty/lua-resty-string) : [BSD License](https://github.com/openresty/lua-resty-string#copyright-and-license)
* [Penlight](https://github.com/lunarmodules/Penlight) : [MIT License](https://github.com/lunarmodules/Penlight/blob/master/LICENSE.md)
* [lua-resty-openssl](https://github.com/fffonion/lua-resty-openssl) : [BSD 2-Clause "Simplified" License](https://github.com/fffonion/lua-resty-openssl/blob/master/LICENSE)
* [lua-resty-http](https://github.com/ledgetech/lua-resty-http) : [BSD 2-Clause "Simplified" License](https://github.com/ledgetech/lua-resty-http/blob/master/LICENSE)
* [lua-cjson](https://github.com/mpx/lua-cjson) : [MIT License](https://github.com/mpx/lua-cjson/blob/master/LICENSE)

## License

[Modified Apache 2.0 (Section 6)](https://github.com/LEGO/kong-aws-request-signing/blob/main/LICENSE)
