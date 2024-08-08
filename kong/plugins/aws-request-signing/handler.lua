local sigv4 = require "kong.plugins.aws-request-signing.sigv4"

local kong = kong
local ngx = ngx
local error = error
local type = type
local json  = require "cjson"

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
  local generic_error = "Error fetching STS credentials. Enable 'return_sts_error' in config for details."
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
      return kong.response.exit(401, {message = generic_error})
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
        return kong.response.exit(401, {message = generic_error})
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
  local final_host = conf.override_target_host or ngx.ctx.balancer_data.host

  if service == nil then
    kong.log.err("Unable to retrieve bound service!")
    return kong.response.exit(500, { message = "The plugin must be bound to a service!" })
  end

  if conf.preserve_auth_header then
    kong.service.request.set_headers({
      [conf.preserve_auth_header_key] = request_headers.authorization
    })
  end

  if conf.override_target_protocol then
    kong.service.request.set_scheme(conf.override_target_protocol)
  end
  if conf.override_target_port and conf.override_target_host then
    kong.service.set_target(conf.override_target_host, conf.override_target_port)
  elseif conf.override_target_host then
    kong.service.set_target(conf.override_target_host, service.port)
  elseif conf.override_target_port then
    kong.service.set_target(final_host, conf.override_target_port)
  end


  local sts_conf = {
    RoleArn = conf.aws_assume_role_arn,
    WebIdentityToken = retrieve_token(request_headers["authorization"]),
    RoleSessionName = conf.aws_assume_role_name,
  }

  local iam_role_credentials = get_iam_credentials(sts_conf, request_headers["x-sts-refresh"],
                                                    conf.return_aws_sts_error)

  -- we only send those two headers for signing
  local upstream_headers = {
    host = final_host,
    -- those will be nill thus we only pass the host on requests without body
    ["content-length"] = request_headers["content-length"],
    ["content-type"] = request_headers["content-type"]
  }

  -- removing the authorization, we either do not need it or we set it again later.
  kong.service.request.clear_header("authorization")

  -- might fail if too big. is controlled by the folowing nginx params:
  -- nginx_http_client_max_body_size
  -- nginx_http_client_body_buffer_size
  local req_body, get_body_err = kong.request.get_raw_body()

  if get_body_err or req_body == nil then
    kong.log.err(get_body_err)
    return kong.response.exit(400, { message = "Request body exceeds size limit and cannot be used by plugins." })
  end

  local sigv4_opts = {
    region = conf.aws_region,
    service = conf.aws_service,
    method = kong.request.get_method(),
    headers = upstream_headers,
    body = req_body,
    path = ngx.var.upstream_uri,
    host = final_host,
    port = service.port,
    query = kong.request.get_raw_query(),
    access_key = iam_role_credentials.access_key,
    secret_key = iam_role_credentials.secret_key,
    session_token = iam_role_credentials.session_token,
    sign_query = conf.sign_query
  }

  local signed_request, sigv4_err = sigv4(sigv4_opts)
  if sigv4_err then
    kong.log.err(sigv4_err)
    return error(sigv4_err)
  end

  if not signed_request then
    return kong.response.exit(500, { message = "Unable to SIGV4 the request!" })
  end

  kong.service.request.set_headers(signed_request.headers)
  kong.service.request.set_raw_query(signed_request.query)
end

AWSLambdaSTS.PRIORITY = 15
AWSLambdaSTS.VERSION = "1.0.5"

return AWSLambdaSTS
