local sigv4 = require "kong.plugins.aws-request-signing.sigv4"

local kong = kong
local ngx = ngx
local error = error
local type = type
local json  = require "cjson"


local get_raw_body = kong.request.get_raw_body

local set_headers = kong.service.request.set_headers
local set_raw_query = kong.service.request.set_raw_query

local IAM_CREDENTIALS_CACHE_KEY_PATTERN = "plugin.aws-request-signing.iam_role_temp_creds.%s"
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

local function get_iam_credentials(sts_conf, refresh, return_sts_error)
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
    if(return_sts_error ~= nil and return_sts_error == true ) then
      local errJson = err:gsub("failed to get from node cache:", "")
      local resError = json.decode(errJson)
      return kong.response.exit(resError.sts_status, { message = resError.message, stsResponse = resError.sts_body })
    else
      return kong.response.exit(401, {message = 'Error fetching STS credentials!'})
    end
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
      if(return_sts_error ~= nil and return_sts_error == true ) then
        local errJson = err:gsub("failed to get from node cache:", "")
        local resError = json.decode(errJson)
        return kong.response.exit(resError.sts_status, { message = resError.message, stsResponse = resError.sts_body })
      else
        return kong.response.exit(401, {message = 'Error fetching STS credentials!'})
      end
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
  local request_headers = kong.request.get_headers()

  if service == nil then
    kong.log.err("Unable to retrieve bound service!")
    return kong.response.exit(500, { message = "Internal error 1!" })
  end

  if conf.override_target_protocol then
    kong.service.request.set_scheme(conf.override_target_protocol)
  end
  if conf.override_target_port and conf.override_target_host then
    kong.service.set_target(conf.override_target_host, conf.override_target_port)
  end
  -- if conf.override_target_host then
  --   kong.service.set_target(conf.override_target_host, service.port)
  -- end


  local sts_conf = {
    RoleArn = conf.aws_assume_role_arn,
    WebIdentityToken = retrieve_token(request_headers["authorization"]),
    RoleSessionName = conf.aws_assume_role_name,
  }

  local iam_role_credentials = get_iam_credentials(sts_conf, request_headers["x-sts-refresh"],
                                                    conf.return_aws_sts_error)

  -- we only send those two headers for signing
  local upstream_headers = {
    host = service.host,
    ["x-authorization"] = request_headers.authorization
  }

  -- removing the authorization, we either do not need it or we set it again later.
  kong.service.request.clear_header("authorization")

  local opts = {
    region = conf.aws_region,
    service = conf.aws_service,
    method = kong.request.get_method(),
    headers = upstream_headers,
    body = get_raw_body(),
    path = ngx.var.upstream_uri,
    host = service.host,
    port = service.port,
    query = kong.request.get_raw_query(),
    access_key = iam_role_credentials.access_key,
    secret_key = iam_role_credentials.secret_key,
    session_token = iam_role_credentials.session_token,
    sign_query = conf.sign_query
  }

  local request, err = sigv4(opts)
  if err then
    return error(err)
  end

  if not request then
    return kong.response.exit(500, { message = "Unable to SIGV4 the request!" })
  end

  set_headers(request.headers)
  set_raw_query(request.query)
end

AWSLambdaSTS.PRIORITY = 110
AWSLambdaSTS.VERSION = "1.0.2"

return AWSLambdaSTS
