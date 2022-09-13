# This document is intended for Developers

### Testing
  *Unit tests are not done yet*

Performance test was done using K6 and 1400 up to 5800 virtual users.

Have a look at the table below:
| Virtual Users | Kong Served | Kong Failed | % Failed | AWS Gateway served | AWS Failed | % Failed |
|---------------|-------------|-------------|----------|--------------------|------------|----------|
| 1400          |   1026502   |    76084    |   6.90%  |       1086040      |     50     | 0        |
| 2200          |   1037397   |    337255   |  24.53%  |       1093566      |   655754   | 37.48%   |
| 2800          |   1037481   |    389040   |  27.27%  |       1044843      |   849726   | 44.85%   |
| 3500          |   1044854   |    327536   |  23.86%  |       843754       |   2005030  | 70.38%   |
| 5800          |   1044899   |    285553   |  21.46%  |       668146       |   3936820  | 85.49%   |

Based on the results above, we assume that this plugin and Kong is more reliable than AWS API Gateway, at least in the case when a lot of users have to be served.

### Plugin Development
Below you will find some actions you might want to perform during plugin development

* #### restarting dev env
  ```sh
  pongo down && pongo run --no-cassandra && pongo shell
  ```

* #### starting kong
  ```sh
  kong migrations bootstrap --force && kong start
  ```

* #### reloading kong
  ```sh
  kong reload
  ```

* #### exporting ENV var used below
  ```sh
  export kong_proxf_url=http://localhost:8000
  export kong_admin_url=http://localhost:8001
  export service_name=echo 
  export plugin_name=aws-request-signing
  export lambda_url=http://example.com
  ```

* #### exporting Token used to AssumeRoleWithWebIdentity
  ```sh
  export auth_token=
  ```

* #### Simple service + route + plugin configuration
  ```sh
  curl -i -X POST \
   --url $kong_admin_url/services/ \
   --data "name=$service_name" \
   --data "url=https://$lambda_url/" && curl -i -X POST \
   --url $kong_admin_url/services/$service_name/routes \
   --data "paths[]=/$service_name" && curl -i -X POST \
   --url $kong_admin_url/services/$service_name/plugins/ \
   --data "name=$plugin_name" \
   --data 'config.aws_assume_role_arn=arn:aws:iam::3000453029296:role/azure-lambda' \
   --data 'config.aws_assume_role_name=azure-lambda'\
   --data 'config.aws_region=eu-west-1' \
   --data 'config.aws_service=lambda' 
  ```

* #### Configuring a service a route and adding the Kong Request-Transformer and this plugin
  ```sh
  curl -i -X POST \
   --url $kong_admin_url/services/ \
   --data "name=$service_name" \
   --data "url=https://$lambda_url/" && curl -i -X POST \
   --url $kong_admin_url/services/$service_name/routes \
   --data "paths[]=/digital/api/(?<g1>$service_name)" && curl -i -X POST \
   --url $kong_admin_url/services/$service_name/plugins/ \
   --data "name=request-transformer" \
   --data 'config.replace.uri=/$(uri_captures.g1)'  && curl -i -X POST \
   --url $kong_admin_url/services/$service_name/plugins/ \
   --data "name=$plugin_name" \
   --data 'config.aws_assume_role_arn=arn:aws:iam::300063049296:role/azure-lambda' \
   --data 'config.aws_assume_role_name=azure-lambda'\
   --data 'config.aws_region=eu-west-1' \
   --data 'config.aws_service=lambda' 
  ```


* #### Simple Kong call (Request-Transformer activated)
  ```sh
  curl -v -H "Authorization: Bearer $auth_token" $kong_proxy_url/digital/api/$service_name 
  ```

* #### Simple Kong call
  ```sh
  curl -v -H "Authorization: Bearer $auth_token" $kong_proxy_url/$service_name
  ```

* #### Complex Kong call 
  ```sh
  curl -v -H "Authorization: Bearer $auth_token" -H "Content-Type: application/json" $kong_proxy_url/$service_name?query=true --data '{"username":"xyz","password":"xyz"}' 
  ```

* #### Complex Kong call (Request-Transformer activated)
  ```sh
  curl -v -H "Authorization: Bearer $auth_token" -H "Content-Type: application/json" $kong_proxy_url/digital/api/$service_name?query=true --data '{"username":"xyz","password":"xyz"}' 
  ```

* #### Just like above with forced credentials refresh.
  ```sh
  curl -v -H "Authorization: Bearer $auth_token" -H "Content-Type: application/json" -H "x-sts-refresh: true" $kong_proxy_url/digital/api/$service_name?query=true --data '{"username":"xyz","password":"xyz"}' 
  ```

* #### Change upstream of the service
  ```sh
  curl -i -X PATCH \
   --url "$kong_admin_url/services/$service_name" \
   --data "url=https://new.example.com/"
  ```

