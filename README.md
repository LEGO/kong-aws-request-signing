## KONG-PLUGIN-AWS-WEBID-ACCESS

This plugin was made to allow the secure use of AWS Lambdas as upstreams in Kong using [Lambda URLs](https://aws.amazon.com/blogs/aws/announcing-aws-lambda-function-urls-built-in-https-endpoints-for-single-function-microservices/). This way we reduce the cost and complexity by bypassing AWS API Gateway.

Some of the code was reused from [Kong Lambda Plugin](https://github.com/Kong/kong/blob/master/kong/plugins/aws-lambda) specifically the [SIGV4 creation](https://github.com/Kong/kong/blob/master/kong/plugins/aws-lambda/v4.lua) code and some parts for [getting the temporary credentials from AWS STS](https://github.com/Kong/kong/blob/master/kong/plugins/aws-lambda/iam-sts-credentials.lua). There are some considerable differences that I will outline below:

1. Unlike Kong-Lambda This plugin does not perform the Lambda invocation. But only signs the request coming from the consumer which Kong then forwards to the upstream that it is configured in the service that the plugin is bound to.
2. The plugin works only with temporary credentials that are fetched from https://sts.amazonaws.com using [AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html#API_AssumeRoleWithWebIdentity_RequestParameters), this requires some configuration in AWS.
3. This plugin has a low priority and is compatible with the rest of Kong plugins because as mentioned above, it only performs SIGV4 on the request and then appends the necessary headers to be authorized in AWS.


Plugin configuration parameters:

```lua
aws_assume_role_arn - ARN of the IAM role that the plugin will try to assume
type = "string"
required = true


aws_assume_role_name - Name of the role above.
type = "string"
required = true


aws_region - Region of the Lambda you are pointing to
type = "string"
required = true


aws_service - AWS Service you are trying to access (lambda)
type = "string"
required = true
```


## License
```
Copyright 2022 The LEGO Group.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```