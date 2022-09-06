-- BSD 2-Clause License
local http  = require "resty.http"
-- MIT License
local json  = require "cjson"
---@diagnostic disable-next-line: undefined-global
local ngx_now = ngx.now
---@diagnostic disable-next-line: undefined-global
local kong = kong

local DEFAULT_SESSION_DURATION_SECONDS = 3600
local DEFAULT_HTTP_CLINET_TIMEOUT = 60000

local function get_regional_sts_endpoint()
    return 'https://sts.amazonaws.com'
end


local function fetch_assume_role_credentials(assume_role_arn,
                                             role_session_name,
                                             web_identity_token)
  if not assume_role_arn then
    return nil, "Missing required parameter 'assume_role_arn' for fetching STS credentials"
  end

  kong.log.debug('Trying to assume role [', assume_role_arn, ']')

  local sts_host = get_regional_sts_endpoint()

  -- build the url and signature to assume role
  local assume_role_request_headers = {
    Accept                    = "application/json"
  }

  local assume_role_query_params = {
    Action          = "AssumeRoleWithWebIdentity",
    DurationSeconds = DEFAULT_SESSION_DURATION_SECONDS,
    RoleArn         = assume_role_arn,
    RoleSessionName = role_session_name,
    Version         = "2011-06-15",
    WebIdentityToken = web_identity_token
  }

  -- Call STS to assume role
  local client = http.new()
  client:set_timeout(DEFAULT_HTTP_CLINET_TIMEOUT)
  local res, err = client:request_uri(sts_host, {
    method = "GET",
    headers = assume_role_request_headers,
    ssl_verify = false,
    query = assume_role_query_params
  })

  if err then
    local err_s = 'Unable to assume role [' ..  assume_role_arn .. ']' ..
                  ' due to: ' .. tostring(err)
    return nil, err_s
  end

  if res.status ~= 200 then
    local err_s = 'Unable to assume role [' .. assume_role_arn .. '] due to:' ..
                  'status [' .. res.status .. '] - ' ..
                  'reason [' .. res.body .. ']'
    return nil, err_s
  end

  local credentials =
    json.decode(res.body).AssumeRoleWithWebIdentityResponse.AssumeRoleWithWebIdentityResult.Credentials

  local result = {
    access_key    = credentials.AccessKeyId,
    secret_key    = credentials.SecretAccessKey,
    session_token = credentials.SessionToken,
    expiration    = credentials.Expiration
  }

  return result, nil, result.expiration - ngx_now()
end


return {
  fetch_assume_role_credentials = fetch_assume_role_credentials,
}
