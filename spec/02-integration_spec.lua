local helpers = require("spec.helpers")
local cjson = require("cjson.safe")
local openssl_hmac = require "resty.openssl.hmac"
local to_hex = require"resty.string".to_hex
local resty_sha256 = require "resty.sha256"

local PLUGIN_NAME = "aws-request-signing"

-- Create a new DNS mock and add some DNS records
local fixtures = {
    http_mock = {},
    stream_mock = {},
    dns_mock = helpers.dns_mock.new()
}
fixtures.dns_mock:A{
    name = "sts.amazonaws.com",
    address = "127.0.0.1"
}
fixtures.dns_mock:A{
    name = "test2a.com",
    address = "127.0.0.1"
}

-- This block is for mocking the call to sts.amazonaws.com
fixtures.http_mock.sts_server_block = [[
  server {
    listen 443 ssl;
    server_name sts.amazonaws.com;
    ssl_certificate /kong/spec/fixtures/kong_spec.crt;
    ssl_certificate_key /kong/spec/fixtures/kong_spec.key;
    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
    location "/" {
      return 200 '{
        "AssumeRoleWithWebIdentityResponse":{
          "AssumeRoleWithWebIdentityResult":{
            "Credentials":{
              "AccessKeyId":"A",
              "SecretAccessKey":"B",
              "SessionToken":"C",
              "Expiration":1726572582
            }
          }
        }
      }';
    }
  }
]]

-- This bloc is for mocking the overrided host specified in one of the tests
fixtures.http_mock.test_server_block = [[
  server {
    listen 9443 ssl;
    server_name test2a.com;
    ssl_certificate /kong/spec/fixtures/kong_spec.crt;
    ssl_certificate_key /kong/spec/fixtures/kong_spec.key;
    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
    location /testoverride {
      return 200 '{"host": "$http_host", "uri": "$uri", "agent":"$http_user_agent"}';
    }
  }
]]

-- These functions are used to calculate the signature for the request
local function hmac(secret, data)
    return openssl_hmac.new(secret, "sha256"):final(data)
end

local function derive_signing_key(kSecret, date, region, service)
    local kDate = hmac("AWS4" .. kSecret, date)
    local kRegion = hmac(kDate, region)
    local kService = hmac(kRegion, service)
    return hmac(kService, "aws4_request")
end

local function hash(str)
    local sha256 = resty_sha256:new()
    sha256:update(str)
    return sha256:final()
end

local function calulate_signature(headers, method, uri)
    local canonical_request = method .. "\n" .. uri .. "\n\nhost:" .. headers["host"] .. "\nx-amz-content-sha256:" ..
                                  headers["x-amz-content-sha256"] .. "\nx-amz-date:" .. headers["x-amz-date"] ..
                                  "\nx-amz-security-token:" .. headers["x-amz-security-token"] ..
                                  "\n\nhost;x-amz-content-sha256;x-amz-date;x-amz-security-token\n" ..
                                  headers["x-amz-content-sha256"]
    local string_to_sign = "AWS4-HMAC-SHA256\n" .. headers["x-amz-date"] .. "\n" ..
                               (string.sub(headers["x-amz-date"], 1, 8)) .. "/eu-west-1/lambda/aws4_request" .. "\n" ..
                               to_hex(hash(canonical_request))
    local signing_key = derive_signing_key("B", string.sub(headers["x-amz-date"], 1, 8), "eu-west-1", "lambda")
    local signature = to_hex(hmac(signing_key, string_to_sign))
    return signature
end

-- Now orchestrate the tests
for _, strategy in helpers.all_strategies() do

    describe("Plugin: " .. PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
        local proxy_client

        lazy_setup(function()
            local bp = helpers.get_db_utils(strategy, nil, {PLUGIN_NAME})

            -- Assets for test: "should place a valid signature in headers by default"
            local route1 = bp.routes:insert({
                hosts = {"test1.com"},
                name = "route1"
            })
            bp.plugins:insert{
                name = PLUGIN_NAME,
                route = {
                    id = route1.id
                },
                config = {
                    aws_region = "eu-west-1",
                    aws_service = "lambda",
                    aws_assume_role_name = "test-role-name",
                    aws_assume_role_arn = "arn:aws:iam::123456789012:role/test-role-name"
                }
            }

            -- Assets for test: "should override host when configured"
            local service2 = bp.services:insert({
                connect_timeout = 1000,
                name = "service2",
                url = "https://test2.com:6443",
                retries = 0
            })
            local route2 = bp.routes:insert({
                name = "route2",
                paths = {"/testoverride"},
                service = service2,
                strip_path = false
            })
            bp.plugins:insert{
                name = PLUGIN_NAME,
                route = {
                    id = route2.id
                },
                config = {
                    aws_region = "eu-west-1",
                    aws_service = "lambda",
                    aws_assume_role_name = "test-role-name",
                    aws_assume_role_arn = "arn:aws:iam::123456789012:role/test-role-name",
                    override_target_host = "test2a.com",
                    override_target_port = 9443
                }
            }

            -- Assets for test: "should place signature information in query string when config enables it"
            local route3 = bp.routes:insert({
                hosts = {"test3.com"},
                name = "route3"
            })
            bp.plugins:insert{
                name = PLUGIN_NAME,
                route = {
                    id = route3.id
                },
                config = {
                    aws_region = "eu-west-1",
                    aws_service = "lambda",
                    aws_assume_role_name = "test-role-name",
                    aws_assume_role_arn = "arn:aws:iam::123456789012:role/test-role-name",
                    sign_query = true
                }
            }

            assert(helpers.start_kong({
                database = strategy,
                nginx_conf = "spec/fixtures/custom_nginx.template",
                plugins = "bundled," .. PLUGIN_NAME
            }, nil, nil, fixtures))
        end)

        lazy_teardown(function()
            helpers.stop_kong(nil, true)
        end)

        before_each(function()
            proxy_client = helpers.proxy_client()
        end)

        after_each(function()
            if proxy_client then
                proxy_client:close()
            end
        end)

        describe("Adding signature to request", function()

            it("should place a valid signature in headers by default", function()
                local res = assert(proxy_client:send{
                    method = "GET",
                    path = "/status/200",
                    headers = {
                        ["Host"] = "test1.com",
                        authorization = "header.body.sig",
                    }
                })
                local body = assert.res_status(200, res)
                local json = cjson.decode(body)
                assert.is.truthy(json.headers["x-amz-content-sha256"])
                assert.is.truthy(json.headers["x-amz-date"])
                assert.is.truthy(json.headers["x-amz-security-token"])
                local calculated_signature = calulate_signature(json.headers, json.vars.request_method, json.vars.uri)
                local _, _, signature_from_header = string.find(json.headers["authorization"], "Signature=(.*)")
                assert.match(calculated_signature, signature_from_header)
            end)

            it("should override host when configured", function()
                local res = proxy_client:get("/testoverride", {
                    headers = {
                        ["Host"] = "test2.com",
                        authorization = "header.body.sig",
                    }
                })
                local body = assert.res_status(200, res)
                local json = cjson.decode(body)
                assert.match("test2a.com", json["host"])
            end)

            it("should place signature information in query string when config 'sign_query' is true", function()
                local res = assert(proxy_client:send{
                    method = "GET",
                    path = "/status/200",
                    headers = {
                        ["Host"] = "test3.com",
                        authorization = "header.body.sig",
                    }
                })
                local body = assert.res_status(200, res)
                local json = cjson.decode(body)
                -- the x-amz-content-sha256 will still be in the header
                assert.is.truthy(json.headers["x-amz-content-sha256"])
                -- check signature info is in the uri
                assert.is.truthy(json.uri_args["X-Amz-Date"])
                assert.is.truthy(json.uri_args["X-Amz-Security-Token"])
                assert.is.truthy(json.uri_args["X-Amz-Signature"])
                -- check signature info is in the headers
                assert.is.falsy(json.headers["x-amz-date"])
                assert.is.falsy(json.headers["x-amz-security-token"])
            end)

        end)
    end)
end
