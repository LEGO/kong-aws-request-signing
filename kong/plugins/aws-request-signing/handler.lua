local sigv4 = require "kong.plugins.aws-request-signing.sigv4"
local meta = require "kong.meta"

local kong = kong
local ngx = ngx
local error = error
local type = type

local set_headers = kong.service.request.set_headers
local get_raw_body = kong.request.get_raw_body
local set_raw_body = kong.service.request.set_raw_body

local IAM_CREDENTIALS_CACHE_KEY_PATTERN = "plugin.aws-request-signing.iam_role_temp_creds.%s"
local AWS_PORT = 443

local AWSLambdaSTS = {}

local function fetch_aws_credentials(sts_conf)
  local sts = require('kong.plugins.aws-request-signing.webidentity-sts-credentials')

  local result, err =
    sts.fetch_assume_role_credentials(sts_conf.RoleArn, sts_conf.RoleSessionName, sts_conf.WebIdentityToken)

  if err then
    return nil, err
  end
  return result, nil
end

local function get_now()
  ngx.update_time()
  return ngx.now() -- time is kept in seconds
end

local function retrieve_token(token_header)
  if token_header then
    if type(token_header) == "table" then
      token_header = token_header[1]
    end

    local captures, err = ngx.re.match(token_header, [[ \s* Bearer \s+ (.+) ]], "joxi", nil)
    if err then
      kong.log.err(err)
    elseif captures then
      return captures[1]
    end
  end
end

if _TEST then
  AWSLambdaSTS._retrieve_token = retrieve_token
end

local function get_iam_credentials(sts_conf, refresh)
  local iam_role_cred_cache_key = string.format(IAM_CREDENTIALS_CACHE_KEY_PATTERN, sts_conf.RoleArn)

  if refresh then
    kong.log.debug("invalidated iam_role cache!")
    kong.cache:invalidate_local(iam_role_cred_cache_key)
  end

  local iam_role_credentials, err = kong.cache:get(
    iam_role_cred_cache_key,
    nil,
    fetch_aws_credentials,
    sts_conf
  )

  if err then
    kong.log.err(err)
    return kong.response.exit(401, { message = "Unable to get the IAM credentials! Check token!" })
  end

  if not iam_role_credentials
    or (get_now() + 60) > iam_role_credentials.expiration then
    kong.cache:invalidate_local(iam_role_cred_cache_key)
    iam_role_credentials, err = kong.cache:get(
      iam_role_cred_cache_key,
      nil,
      fetch_aws_credentials,
      sts_conf
    )
    if err then
      kong.log.err(err)
      return kong.response.exit(401, { message = "Unable to refresh expired IAM credentials! Check token!" })
    end
    kong.log.debug("expiring key , invalidated iam_cache and fetched fresh credentials!")
  end
  return iam_role_credentials
end

if _TEST then
  AWSLambdaSTS._get_iam_credentials = get_iam_credentials
end

function AWSLambdaSTS:access(conf)
  local service = kong.router.get_service()

  if service == nil then
    kong.log.err("Unable to retrieve bound service!")
    return kong.response.exit(500, { message = "Internal server error" })
  end

  local request_headers = kong.request.get_headers()

  local sts_conf = {
    RoleArn = conf.aws_assume_role_arn,
    WebIdentityToken = retrieve_token(request_headers["authorization"]),
    RoleSessionName = conf.aws_assume_role_name,
  }

  local iam_role_credentials = get_iam_credentials(sts_conf, request_headers["x-sts-refresh"])

  local upstream_headers = {
    ["x-authorization"] = kong.request.get_headers().authorization,
    ["x-amz-security-token"] = iam_role_credentials.session_token,
    host = service.host,
  }

  local opts = {
    region = conf.aws_region,
    service = conf.aws_service,
    method = kong.request.get_method(),
    headers = upstream_headers,
    body = get_raw_body(),
    path = ngx.var.upstream_uri,
    host = service.host,
    port = AWS_PORT,
    query = kong.request.get_raw_query(),
    access_key = iam_role_credentials.access_key,
    secret_key = iam_role_credentials.secret_key,
  }

  local request, err = sigv4(opts)
  if err then
    return error(err)
  end

  if not request then
    return kong.response.exit(500, { message = "Unable to SIGV4 the request!" })
  end

  set_headers(request.headers)
  set_raw_body(request.body)
end

AWSLambdaSTS.PRIORITY = 110
AWSLambdaSTS.VERSION = meta.version

return AWSLambdaSTS
