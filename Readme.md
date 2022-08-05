## KONG-PLUGIN-AWS-SIGV4-WEBID-AUTH

### About

This plugin was made to allow the secure use of AWS Lambdas as upstreams in Kong using [Lambda URLs](https://aws.amazon.com/blogs/aws/announcing-aws-lambda-function-urls-built-in-https-endpoints-for-single-function-microservices/).
It reduces cost and complexity by excluding AWS API Gateway. The required AWS setup to make the plugin work with your Lambda HTTPS endpoint will be described below.

## AWS Setup required
1. You have a [Lambda function](https://eu-west-1.console.aws.amazon.com/lambda/home?region=eu-west-1#) deployed with `Function URL` enabled and Auth type : `AWS_IAM`

![image](https://user-images.githubusercontent.com/29011940/183050407-553a5ea9-f746-4baa-8b41-3a88b852ec4b.png)

2. Your OpenID Connect provider is added to [AWS IAM](https://us-east-1.console.aws.amazon.com/iamv2/home?region=us-east-1#/identity_providers)
3. You have a role with  `arn:aws:iam::aws:policy/AWSLambda_FullAccess` permision and the trust relationship below:
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

So if your provider is `https://sts.windows.net/organization.onmicrosoft.com/` and your app identity is `app_identity_1`, the trust relationship above will look like:

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

## About the code and differences from [Kong Lambda Plugin](https://github.com/Kong/kong/blob/master/kong/plugins/aws-lambda)
Some of the code was reused from [Kong Lambda Plugin](https://github.com/Kong/kong/blob/master/kong/plugins/aws-lambda) specifically the [SIGV4 creation](https://github.com/Kong/kong/blob/master/kong/plugins/aws-lambda/v4.lua) code and some parts for [getting the temporary credentials from AWS STS](https://github.com/Kong/kong/blob/master/kong/plugins/aws-lambda/iam-sts-credentials.lua). There are some considerable differences that I will outline below:

1. Unlike Kong-Lambda This plugin does not perform the Lambda invocation. But only signs the request coming from the consumer which Kong then forwards to the upstream that it is configured in the service that the plugin is bound to.
2. The plugin works only with temporary credentials that are fetched from https://sts.amazonaws.com using [AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html#API_AssumeRoleWithWebIdentity_RequestParameters), this requires some configuration in AWS.
3. This plugin has a low priority and is compatible with the rest of Kong plugins because as mentioned above, it only performs SIGV4 on the request and then appends the necessary headers to be authorized in AWS.


### Plugin configuration parameters:

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
```



### License 
[Modified Apache 2.0 (Section 6)](https://github.com/LEGO/kong-plugin-aws-sigv4-webid-auth/blob/main/LICENSE)
