-- Copyright (C) Kong Inc.

local aws_v4 = require "kong.plugins.aws-webid-access.sigv4"
local http = require "resty.http"
local cjson = require "cjson.safe"
local meta = require "kong.meta"
local constants = require "kong.constants"
local request_util = require "kong.plugins.aws-webid-access.request-util"
local kong = kong
local GLOBAL_QUERY_OPTS = { workspace = ngx.null, show_ws_id = true }

local table_insert = table.insert
local get_uri_args = kong.request.get_query
local set_uri_args = kong.service.request.set_query
local clear_header = kong.service.request.clear_header
local get_header = kong.request.get_header
local set_header = kong.service.request.set_header
local get_headers = kong.request.get_headers
local set_headers = kong.service.request.set_headers
local set_method = kong.service.request.set_method
local set_path = kong.service.request.set_path
local get_raw_body = kong.request.get_raw_body
local set_raw_body = kong.service.request.set_raw_body
local set_body = kong.service.request.set_body
local encode_args = ngx.encode_args
local ngx_decode_args = ngx.decode_args

local VIA_HEADER = constants.HEADERS.VIA
local VIA_HEADER_VALUE = meta._NAME .. "/" .. meta._VERSION
local IAM_CREDENTIALS_CACHE_KEY_PATTERN = "plugin.aws-webid-access.iam_role_temp_creds.%s"
local AWS_PORT = 443
local re_gmatch = ngx.re.gmatch

local function isEmpty(s)
    return s == nil or s == ''
end

local function split (inputstr, sep)
  if sep == nil then
          sep = "%s"
  end
  local t={}
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
          table.insert(t, str)
  end
  return t
end

local function load_service_from_db(service_pk)
  local service, err = kong.db.services:select(service_pk, GLOBAL_QUERY_OPTS)
  if service == nil then
    -- the third value means "do not cache"
    return nil, err, -1
  end
  return service
end

local function fetch_aws_credentials(sts_conf)
  local sts = require('kong.plugins.aws-webid-access.webidentity-sts-credentials')

  local result = sts.fetch_assume_role_credentials(sts_conf.RoleArn, sts_conf.RoleSessionName, sts_conf.WebIdentityToken);
  kong.log.debug(result)
  return result
end


local ngx_encode_base64 = ngx.encode_base64
local ngx_decode_base64 = ngx.decode_base64
local ngx_update_time = ngx.update_time
local tostring = tostring
local tonumber = tonumber
local ngx_now = ngx.now
local ngx_var = ngx.var
local error = error
local pairs = pairs
local kong = kong
local type = type
local fmt = string.format


local raw_content_types = {
  ["text/plain"] = true,
  ["text/html"] = true,
  ["application/xml"] = true,
  ["text/xml"] = true,
  ["application/soap+xml"] = true,
}


local function get_now()
  ngx_update_time()
  return ngx_now() * 1000 -- time is kept in seconds with millisecond resolution.
end


local function retrieve_token()
  local request_headers = kong.request.get_headers()
  for _, v in ipairs({"authorization"}) do
    local token_header = request_headers[v]
    if token_header then
      if type(token_header) == "table" then
        token_header = token_header[1]
      end
      local iterator, iter_err = re_gmatch(token_header, "\\s*[Bb]earer\\s+(.+)")
      if not iterator then
        kong.log.err(iter_err)
        break
      end

      local m, err = iterator()
      if err then
        kong.log.err(err)
        break
      end

      if m and #m > 0 then
        return m[1]
      end
    end
  end
end

local AWSLambdaSTS = {}

local function get_iam_credentials(sts_conf)

  local iam_role_cred_cache_key = fmt(IAM_CREDENTIALS_CACHE_KEY_PATTERN, sts_conf.RoleArn or "default")
  local iam_role_credentials = kong.cache:get(
    iam_role_cred_cache_key,
    nil,
    fetch_aws_credentials,
    sts_conf
  )

  local expires = 0;

  if iam_role_credentials then
    expires = iam_role_credentials.expiration
  end
  local now = math.floor(get_now() / 1000)

  if((now+60)>=expires) then
    iam_role_credentials, err = fetch_aws_credentials(sts_conf)
    if err then
      return kong.response.exit(401, { message = "Unable to get new IAM credentials! Check token!"})
    end
    kong.log.inspect("key expiring")
    kong.cache:invalidate_local(iam_role_cred_cache_key)
    local err
    kong.log.inspect(err);
    kong.log.inspect("invalidated cache and fetched fresh credentials")
  else
    kong.log.inspect("key not expiring")
  end

  return iam_role_credentials
end

function AWSLambdaSTS:access(conf)
  local service = kong.router.get_service()

  if service == nil then
    return kong.response.exit(500, { message = "Unable to retrive bound service!"})
  end
  local host = service.host

  local region = conf.aws_region
  local port = AWS_PORT
  local sts_conf = {
     RoleArn = conf.aws_assume_role_arn,
     WebIdentityToken = retrieve_token(),
     RoleSessionName = conf.aws_assume_role_name,
  }

  kong.log.inspect(conf)
  kong.log.inspect(service)
  kong.log.inspect("data above")

  local upstream_body = kong.table.new(0, 6)

  if conf.forward_request_body or
    conf.forward_request_headers or
    conf.forward_request_method or
    conf.forward_request_uri then

  -- new behavior to forward request method, body, uri and their args
  if conf.forward_request_method then
    upstream_body.request_method = kong.request.get_method()
  end

  if conf.forward_request_headers then
    upstream_body.request_headers = kong.request.get_headers()
  end

  if conf.forward_request_uri then
    upstream_body.request_uri = kong.request.get_path()
    upstream_body.request_uri_args = kong.request.get_raw_query()
  end

  if conf.forward_request_body then
    local content_type = kong.request.get_header("content-type")
    local body_raw = request_util.read_request_body(conf.skip_large_bodies)
    local body_args, err = kong.request.get_body()
    if err and err:match("content type") then
      body_args = {}
      if not raw_content_types[content_type] and conf.base64_encode_body then
        -- don't know what this body MIME type is, base64 it just in case
        body_raw = ngx_encode_base64(body_raw)
        upstream_body.request_body_base64 = true
      end
    end

    upstream_body.request_body      = body_raw
    upstream_body.request_body_args = body_args
  end

  else
    -- backwards compatible upstream body for configurations not specifying
    -- `forward_request_*` values
    local body_args = kong.request.get_body()
    upstream_body = kong.table.merge(kong.request.get_query(), body_args)
  end

  local upstream_body_json, err = cjson.encode(upstream_body.request_body_args)
  if not upstream_body_json then
    kong.log.err("could not JSON encode upstream body",
                 " to forward request values: ", err)
  end

  kong.log.inspect("trying to get the key")
  
  if get_iam_credentials(sts_conf) then
    kong.log.inspect("not error")
  else
    kong.log.inspect("error")
    return kong.response.exit(401, { message = "Unable to get new IAM credentials! Check token!"})
  end

  local iam_role_credentials = get_iam_credentials(sts_conf)

  kong.log.inspect(iam_role_credentials)

  if not iam_role_credentials then
    return kong.response.exit(401, { message = "Unable to get new IAM credentials! Check token!"})
  end

  upstream_body.request_headers["original-authorization"] = upstream_body.request_headers.authorization
  upstream_body.request_headers["x-amz-security-token"] = iam_role_credentials.session_token
  upstream_body.request_headers.authorization = nil
  upstream_body.request_headers.host = host

  local opts = {
    region = region,
    service = conf.aws_service,
    method = upstream_body.request_method,
    headers = kong.table.merge(upstream_body.request_headers, {
      ["Content-Length"] = upstream_body_json and tostring(#upstream_body_json),
    }),
    body = upstream_body_json,
    path = ngx_var.upstream_uri,
    host = host,
    port = port,
    query = upstream_body.request_uri_args
  }

  
  -- no credentials provided, so try the IAM metadata service
  

  opts.access_key = iam_role_credentials.access_key
  opts.secret_key = iam_role_credentials.secret_key

  local request
  request, err = aws_v4(opts)
  if err then
    return error(err)
  end

  kong.log.inspect(request);

  -- kong.log.inspect(get_raw_body())
  -- kong.log.inspect(request.body)

  -- kong.log.inspect(request.headers)
  -- kong.log.inspect(get_headers())

  set_headers(request.headers)
  set_raw_body(request.body)

  -- kong.log.inspect(get_headers())
  -- kong.log.inspect(get_raw_body())
  -- kong.log.inspect(get_uri_args())

  local client = http.new()
  client:set_timeout(conf.timeout)
  local kong_wait_time_start = get_now()

  -- comment/uncomment under this line to toggle kong/lua request

  -- kong.log.inspect("sending request");

  -- local res, err = client:request_uri(request.url, {
  --   method = upstream_body.request_method,
  --   body = request.body,
  --   headers = request.headers,
  --   ssl_verify = false,
  --   proxy_opts = proxy_opts,
  --   keepalive_timeout = conf.keepalive,
  -- })
  -- if not res then
  --   return error(err)
  -- end

  -- local content = res.body

  -- kong.log.inspect("response of request");

  -- -- setting the latency here is a bit tricky, but because we are not
  -- -- actually proxying, it will not be overwritten
  -- ctx.KONG_WAITING_TIME = get_now() - kong_wait_time_start
  -- local headers = res.headers

  -- if ngx_var.http2 then
  --   headers["Connection"] = nil
  --   headers["Keep-Alive"] = nil
  --   headers["Proxy-Connection"] = nil
  --   headers["Upgrade"] = nil
  --   headers["Transfer-Encoding"] = nil
  -- end

  -- local status

  -- if not status then
  --   if conf.unhandled_status
  --     and headers["X-Amz-Function-Error"] == "Unhandled"
  --   then
  --     status = conf.unhandled_status

  --   else
  --     status = res.status
  --   end
  -- end

  -- headers = kong.table.merge(headers) -- create a copy of headers

  -- if kong.configuration.enabled_headers[VIA_HEADER] then
  --   headers[VIA_HEADER] = VIA_HEADER_VALUE
  -- end

  -- return kong.response.exit(status, content, headers)
end

AWSLambdaSTS.PRIORITY = -19999
AWSLambdaSTS.VERSION = meta.version

return AWSLambdaSTS
