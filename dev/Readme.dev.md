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

Based on the results above, we assume that this plugin and Kong is more reliable than AWS API Gateway, at least in the case when a lot uf users have to be served.

#### To perform testing on an EC2 instance:

* Configure network
```sh
sudo sysctl -w net.ipv4.ip_local_port_range="1024 65535" && sudo sysctl -w net.ipv4.tcp_tw_reuse=1 && sudo sysctl -w net.ipv4.tcp_timestamps=1 && ulimit -n 250000
```

* Run `test.js`
```sh
k6 run test.js
```

* After testing, results will show up:

```sh
running (2m15.2s), 0000/2200 VUs, 1374652 complete and 0 interrupted iterations
default ✓ [======================================] 0000/2200 VUs  2m15s

     data_received..................: 4.3 GB  32 MB/s
     data_sent......................: 231 MB  1.7 MB/s
     http_req_blocked...............: avg=6.33µs   min=128ns    med=214ns    max=57.8ms   p(90)=302ns    p(95)=323ns
     http_req_connecting............: avg=1.02µs   min=0s       med=0s       max=34.6ms   p(90)=0s       p(95)=0s
   ✓ http_req_duration..............: avg=58.01ms  min=3.31ms   med=20.62ms  max=2.31s    p(90)=133.11ms p(95)=249.25ms
       { expected_response:true }...: avg=65.16ms  min=6.72ms   med=22.63ms  max=2.31s    p(90)=152.74ms p(95)=276.33ms
     http_req_failed................: 24.53%  ✓ 337255       ✗ 1037397
     http_req_receiving.............: avg=43.69µs  min=11.77µs  med=29.02µs  max=162.59ms p(90)=55.33µs  p(95)=73.2µs
     http_req_sending...............: avg=37.48µs  min=19.71µs  med=31.87µs  max=25.49ms  p(90)=44.67µs  p(95)=51.19µs
     http_req_tls_handshaking.......: avg=4.44µs   min=0s       med=0s       max=37.29ms  p(90)=0s       p(95)=0s
     http_req_waiting...............: avg=57.93ms  min=3.25ms   med=20.54ms  max=2.31s    p(90)=133ms    p(95)=249.18ms
     http_reqs......................: 1374652 10171.278848/s
     iteration_duration.............: avg=208.23ms min=153.43ms med=170.83ms max=2.46s    p(90)=283.37ms p(95)=399.5ms
     iterations.....................: 1374652 10171.278848/s
     vus............................: 112     min=112        max=2200
     vus_max........................: 2200    min=2200       max=2200
```

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

