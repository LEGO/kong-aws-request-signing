local aws_v4 = require "kong.plugins.aws-webid-access.sigv4"
local meta = require "kong.meta"
local kong = kong

local set_headers = kong.service.request.set_headers
local get_raw_body = kong.request.get_raw_body
local set_raw_body = kong.service.request.set_raw_body

local IAM_CREDENTIALS_CACHE_KEY_PATTERN = "plugin.aws-webid-access.iam_role_temp_creds.%s"
local AWS_PORT = 443
local re_gmatch = ngx.re.gmatch

local function fetch_aws_credentials(sts_conf)
  local sts = require('kong.plugins.aws-webid-access.webidentity-sts-credentials')

  local result = sts.fetch_assume_role_credentials(sts_conf.RoleArn, sts_conf.RoleSessionName, sts_conf.WebIdentityToken);
  kong.log.debug(result)
  return result
end

local ngx_update_time = ngx.update_time
local tostring = tostring
local ngx_now = ngx.now
local ngx_var = ngx.var
local error = error
local kong = kong
local type = type
local fmt = string.format

local function get_now()
  ngx_update_time()
  return ngx_now() -- time is kept in seconds
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
  local now = get_now()
  local err

  if((now+60)>=expires) then
    iam_role_credentials, err = fetch_aws_credentials(sts_conf)
    if err then
      kong.log.inspect(err);
      return kong.response.exit(401, { message = "Unable to get new IAM credentials! Check token!"})
    end
    kong.cache:invalidate_local(iam_role_cred_cache_key)
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

  local upstream_headers = kong.request.get_headers()
  
  if get_iam_credentials(sts_conf) then
    kong.log.inspect("not error")
  else
    kong.log.inspect("error")
    return kong.response.exit(401, { message = "Unable to get new IAM credentials! Check token!"})
  end

  local iam_role_credentials = get_iam_credentials(sts_conf)

  if not iam_role_credentials then
    return kong.response.exit(401, { message = "Unable to get new IAM credentials! Check token!"})
  end

  upstream_headers["original-authorization"] = upstream_headers.authorization
  upstream_headers["x-amz-security-token"] = iam_role_credentials.session_token
  upstream_headers.authorization = nil
  upstream_headers.host = host

  local opts = {
    region = region,
    service = conf.aws_service,
    method = kong.request.get_method(),
    headers = kong.table.merge(upstream_headers, {
      ["Content-Length"] = kong.request.get_raw_query() and tostring(#kong.request.get_raw_query()),
    }),
    body = get_raw_body(),
    path = ngx_var.upstream_uri,
    host = host,
    port = port,
    query = kong.request.get_raw_query(),
    access_key = iam_role_credentials.access_key,
    secret_key = iam_role_credentials.secret_key,
  }

  local request, err = aws_v4(opts)
  if err then
    return error(err)
  end

  if not request then
    return kong.response.exit(500, { message = "Unable to get SIGV4 the request!"})
  end

  set_headers(request.headers)
  set_raw_body(request.body)
end

AWSLambdaSTS.PRIORITY = 20
AWSLambdaSTS.VERSION = meta.version

return AWSLambdaSTS
