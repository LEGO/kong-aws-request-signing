## KONG-PLUGIN-AWS-SIGV4-WEBID-AUTH

### About

This plugin was made to allow the secure use of AWS Lambdas as upstreams in Kong using [Lambda URLs](https://aws.amazon.com/blogs/aws/announcing-aws-lambda-function-urls-built-in-https-endpoints-for-single-function-microservices/).
It reduces cost and complexity by excluding AWS API Gateway.

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


aws_region - Region of the Lambda you deployed in AWS.
type = "string"
required = true


aws_service - AWS Service you are trying to access (lambda)
type = "string"
required = true
```


### License 
[Modified Apache 2.0 (Section 6)](https://github.com/LEGO/kong-plugin-aws-sigv4-webid-auth/blob/main/LICENSE)
