local kong                              = kong
local ngx                               = ngx
local sigv4                             = require "kong.plugins.aws-request-signing.sigv4"
local util                              = require "kong.plugins.aws-request-signing.util"

local plugin = {}

function plugin:access(conf)
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

  local balancer_host = ngx.ctx.balancer_data.host
  local balancer_port = ngx.ctx.balancer_data.port
  local signed_host = balancer_host
  local signed_port = balancer_port
  local target_altered = (balancer_host ~= service.host) or (balancer_port ~= service.port)

  if conf.override_target_protocol then
    kong.service.request.set_scheme(conf.override_target_protocol)
  end

  local perform_override = true
  if conf.use_altered_target and target_altered then
    perform_override = false
  end

  if perform_override and (conf.override_target_host or conf.override_target_port) then
    signed_host = conf.override_target_host or signed_host
    signed_port = conf.override_target_port or signed_port
    kong.service.set_target(signed_host, signed_port)
  end


  local sts_conf = {
    RoleArn = conf.aws_assume_role_arn or
    ('arn:aws:iam::' .. conf.aws_account_id .. ':role/' .. conf.aws_assume_role_name),
    WebIdentityToken = util.retrieve_token(auth_header_value),
    RoleSessionName = conf.aws_assume_role_name,
  }

  local iam_role_credentials = util.get_iam_credentials(sts_conf, request_headers["x-sts-refresh"],
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
  -- https://github.com/Kong/kong/blob/58f2daa56b90615f78d5953229936192cd1128e9/kong/pdk/request.lua#L714
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
  if sigv4_err or not signed_request then
    kong.log.err(sigv4_err or "Unable to SIGV4 the request!")
    return kong.response.exit(500, { message = sigv4_err or "Unable to SIGV4 the request!" })
  end

  kong.service.request.set_headers(signed_request.headers)
  kong.service.request.set_raw_query(signed_request.query)
end

plugin.PRIORITY = 15
plugin.VERSION = "1.1.0"

return plugin
