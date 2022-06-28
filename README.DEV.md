# This document is intended for Developers
## Below you will find some actions you might want to perform during plugin development

### 1. restarting dev env
```sh
pongo down && pongo run --no-cassandra && pongo shell
```

### 2. starting kong
```sh
kong migrations bootstrap --force && kong start
```

### 3. reloading kong
```sh
kong reload
```

### 4. exporting ENV var used below
```sh
export service_name=echo && export plugin_name=aws-webid-access && export lambda_url={your lambda function url}
```

### 5. exporting Token used to AssumeRoleWithWebIdentity
```sh
export auth_token=
```


### 6. Configuring a service a route and adding the Kong Request-Transformer and this plugin
```sh
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
```

### 7. Simple service + route + plugin configuration
```sh
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
```

### 8. Simple Kong call -> Fits No 6
```sh
curl -v -H "Authorization: Bearer $auth_token" http://localhost:8000/digital/api/$service_name 
```

### 9. Simple Kong call -> Fits No 7
```sh
curl -v -H "Authorization: Bearer $auth_token" http://localhost:8000/$service_name
```

### 10. Complex Kong call -> Fits No 6 (with Body)
```sh
curl -v -H "Authorization: Bearer $auth_token" -H "Content-Type: application/json" http://localhost:8000/digital/api/$service_name?query=true --data '{"username":"xyz","password":"xyz"}' 
```


### 11. Complex Kong call -> Fits No 7 (with Body)  
```sh
curl -v -H "Authorization: Bearer $auth_token" -H "Content-Type: application/json" http://localhost:8000/$service_name?query=true --data '{"username":"xyz","password":"xyz"}' 
```


### 12. Just like above with forced credentials refresh.
```sh
curl -v -H "Authorization: Bearer $auth_token" -H "Content-Type: application/json" -H "x-sts-refresh: true" http://localhost:8000/digital/api/$service_name?query=true --data '{"username":"xyz","password":"xyz"}' 
```

### 13. Change upstream of the service
```sh
curl -i -X PATCH \
 --url "http://localhost:8001/services/$service_name" \
 --data "url=https://{your new upstream}/"
```

