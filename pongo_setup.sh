pongo down && pongo run --no-cassandra && pongo shell

kong migrations bootstrap --force && kong start

export service_name=echo && export plugin_name=aws-webid-access && export lambda_url=odxij524stle6wxmjcj5cnz65e0sroxk.lambda-url.eu-west-1.on.aws

export auth_token=

// config close to the default amma conf

curl -i -X POST \
 --url http://localhost:8001/services/ \
 --data "name=$service_name" \
 --data "url=https://$lambda_url/" && curl -i -X POST \
 --url http://localhost:8001/services/$service_name/routes \
 --data "paths[]=/digital/api/(?<g1>$service_name)" && curl -i -X POST \
 --url http://localhost:8001/services/$service_name/plugins/ \
 --data "name=request-transformer" \
 --data 'config.replace.uri=/$(uri_captures.g1)'  && curl -i -X POST \
 --url http://localhost:8001/services/$service_name/plugins/ \
 --data "name=$plugin_name" \
 --data 'config.aws_assume_role_arn=arn:aws:iam::300063049296:role/azure-lambda' \
 --data 'config.aws_assume_role_name=azure-lambda'\
 --data 'config.aws_region=eu-west-1' \
 --data 'config.aws_service=lambda' 

// simple config

curl -i -X POST \
 --url http://localhost:8001/services/ \
 --data "name=$service_name" \
 --data "url=https://$lambda_url/" && curl -i -X POST \
 --url http://localhost:8001/services/$service_name/routes \
 --data "paths[]=/$service_name" && curl -i -X POST \
 --url http://localhost:8001/services/$service_name/plugins/ \
 --data "name=$plugin_name" \
 --data 'config.aws_assume_role_arn=arn:aws:iam::300063049296:role/azure-lambda' \
 --data 'config.aws_assume_role_name=azure-lambda'\
 --data 'config.aws_region=eu-west-1' \
 --data 'config.aws_service=lambda' 


curl -v -H "Authorization: Bearer $auth_token" http://localhost:8000/digital/api/$service_name

curl -v -H "Authorization: Bearer $auth_token" -H "Content-Type: application/json" http://localhost:8000/$service_name?query=true \
  --data '{"username":"xyz","password":"xyz"}' 
  
  
curl -v -H "Authorization: Bearer $auth_token" -H "Content-Type: application/json" https://dev.api.legogroup.io/echo?query=true \
  --data '{"username":"xyz","password":"xyz"}' 

kong reload && kong reload && kong reload

curl -i -X PATCH \
 --url "http://localhost:8001/services/$service_name" \
 --data "url=https://$lambda_url/"
 
 curl -i -X PATCH \
 --url "http://localhost:8001/services/$service_name" \
 --data "url=https://dev.api.legogroup.io/"

# todo
# + ( feature not bug) create a different cache key ( one client can sign the rest's requests)
# 
# 
# 
# 
# 
# 
