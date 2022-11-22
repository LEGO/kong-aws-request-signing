# KONG-AWS-REQUEST-SIGNING

[![Build](https://github.com/LEGO/kong-aws-request-signing/actions/workflows/build.yml/badge.svg)](https://github.com/LEGO/kong-aws-request-signing/actions/workflows/build.yml)

## About

This plugin will sign a request with AWS SIGV4 and temporary credentials from `sts.amazonaws.com` requested using an OAuth token.

It enables the secure use of AWS Lambdas as upstreams in Kong using [Lambda URLs](https://aws.amazon.com/blogs/aws/announcing-aws-lambda-function-urls-built-in-https-endpoints-for-single-function-microservices/).

At the same time it drives down cost and complexity by excluding the AWS API Gateway and allowing to use AWS Lambdas directly.

The required AWS setup to make the plugin work with your Lambda HTTPS endpoint is described below.

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

aws_service - AWS Service you are trying to access (lambda)
type = "string"
required = true

override_target_host - To be used when deploying multiple lambdas on a single Kong service (because lambdas have differennt URLs)
type = "string"
required = false

override_target_port - To be used when deploying a lambda on a Kong service that listens on a port other than `443`
type = "number"
required = false

override_target_protocol - To be used when deployinglambda on a Kong service that has a protocol different than `https`
type = "string",
one_of = "http", "https"
required = false
```

## Service vs Route scoped configuration

The plugin can be enabled on a per service as well as on a per route basis.

When enabling the plugin on a service/route, the plugin will use the service upstream as the lambda target, unless `override_target_host` is specified.
This configuration works fine only if a single Lambda is used in the entire service, if multiple lambdas are specified on a per path basis, without the `override_target_host` configured, they will all use the service upstream as the target, which will obviously fail.

***TLDR: If multiple lambdas are required for a single Kong service (which most likely is the case), the correct configuration is having a Kong route for each Lambda, enabling the plugin o a per-route basis with `override_target_host` on each of them, so the requests are routed to the right lambda.***

## AWS Setup required

1. You have a [Lambda function](https://eu-west-1.console.aws.amazon.com/lambda/home?region=eu-west-1#) deployed with `Function URL` enabled and Auth type : `AWS_IAM`

<details>
<summary>Show image</summary>
<br>

![Lambda example](https://user-images.githubusercontent.com/29011940/183050407-553a5ea9-f746-4baa-8b41-3a88b852ec4b.png)
</details>

2. Your OpenID Connect provider is added to [AWS IAM](https://us-east-1.console.aws.amazon.com/iamv2/home?region=us-east-1#/identity_providers)
3. You have a role with  `arn:aws:iam::aws:policy/AWSLambda_FullAccess` permision and the trust relationship below:

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
