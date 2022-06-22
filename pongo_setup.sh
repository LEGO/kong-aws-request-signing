pongo down && pongo run --no-cassandra && pongo shell

kong migrations bootstrap --force && kong start

export service_name=example && export plugin_name=aws-webid-access && export lambda_url=odxij524stle6wxmjcj5cnz65e0sroxk.lambda-url.eu-west-1.on.aws

export auth_token= 


curl -i -X POST \
 --url http://localhost:8001/services/ \
 --data "name=$service_name" \
 --data "url=https://$lambda_url" && curl -i -X POST \
 --url http://localhost:8001/services/$service_name/routes \
 --data "paths[]=/$service_name" && curl -i -X POST \
 --url http://localhost:8001/services/$service_name/plugins/ \
 --data "name=$plugin_name" \
 --data 'config.aws_assume_role_arn=arn:aws:iam::300063049296:role/azure-lambda' \
 --data 'config.aws_assume_role_name=azure-lambda'\
 --data 'config.aws_region=eu-west-1' 


curl -v -H "Authorization: Bearer $auth_token" http://localhost:8000/$service_name

curl -i -X PATCH \
 --url "http://localhost:8001/services/$service_name" \
 --data "url=https://$lambda_url"

# todo
# + ( feature not bug) create a different cache key ( one client can sign the rest's requests)
# 
# 
# 
# 
# 
# 
