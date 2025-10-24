local sigv4                             = require "kong.plugins.aws-request-signing.sigv4"

local kong                              = kong
local ngx                               = ngx
local error                             = error
local type                              = type
local json                              = require "cjson"

local IAM_CREDENTIALS_CACHE_KEY_PATTERN = "plugin.aws-request-signing.iam_role_temp_creds.%s"
local AWSLambdaSTS                      = {}

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
    if (return_sts_error ~= nil and return_sts_error == true) then
      local errJson = err:gsub("failed to get from node cache:", "")
      local resError = json.decode(errJson)
      return kong.response.exit(resError.sts_status, { message = resError.message, stsResponse = resError.sts_body })
    else
      return kong.response.exit(401, { message = generic_error })
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
      if (return_sts_error ~= nil and return_sts_error == true) then
        local errJson = err:gsub("failed to get from node cache:", "")
        local resError = json.decode(errJson)
        return kong.response.exit(resError.sts_status, { message = resError.message, stsResponse = resError.sts_body })
      else
        return kong.response.exit(401, { message = generic_error })
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
    return kong.response.exit(500, { message = "The plugin must be bound to a service!" })
  end

  local auth_header_key = conf.auth_header or "authorization"
  local auth_header_value = request_headers[auth_header_key]
  if not auth_header_value then
    kong.log.notice("header value missing for: '" .. auth_header_key .. "', skipping signing")
    return
  end

  if conf.preserve_auth_header then
    kong.service.request.set_headers({
      [conf.preserve_auth_header_key] = auth_header_value
    })
  end
  -- removing the header, we either do not need it or we set it to the signed value later.
  kong.service.request.clear_header(auth_header_key)

  local target_altered = false

  local balancer_host = ngx.ctx.balancer_data.host
  local balancer_port = ngx.ctx.balancer_data.port
  local signed_host = balancer_host
  local signed_port = balancer_port

  if balancer_host ~= service.host then
    target_altered = true
  end
  if balancer_port ~= service.port then
    target_altered = true
  end


  if conf.override_target_protocol then
    kong.service.request.set_scheme(conf.override_target_protocol)
  end

  local perform_override = true
  if conf.use_altered_target and target_altered then
    perform_override = false
  end

  if perform_override then
    if conf.override_target_port and conf.override_target_host then
      signed_host = conf.override_target_host
      signed_port = conf.override_target_port
      kong.service.set_target(conf.override_target_host, conf.override_target_port)
    elseif conf.override_target_host then
      signed_host = conf.override_target_host
      kong.service.set_target(conf.override_target_host, signed_port)
    elseif conf.override_target_port then
      signed_port = conf.override_target_port
      kong.service.set_target(signed_host, conf.override_target_port)
    end
  end


  local sts_conf = {
    RoleArn = conf.aws_assume_role_arn or
    ('arn:aws:iam::' .. conf.aws_account_id .. ':role/' .. conf.aws_assume_role_name),
    WebIdentityToken = retrieve_token(auth_header_value),
    RoleSessionName = conf.aws_assume_role_name,
  }

  local iam_role_credentials = get_iam_credentials(sts_conf, request_headers["x-sts-refresh"],
    conf.return_aws_sts_error)

  -- we only send those headers for signing
  local upstream_headers = {
    host = signed_host,
    -- those will be nil which means that we only pass the host on requests without body
    ["content-length"] = request_headers["content-length"],
    ["content-type"] = request_headers["content-type"]
  }

  -- might fail if too big. is controlled by the following nginx params:
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
    host = signed_host,
    port = signed_port,
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
AWSLambdaSTS.VERSION = "1.0.8"

return AWSLambdaSTS
