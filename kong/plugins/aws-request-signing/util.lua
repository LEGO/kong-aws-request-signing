local kong = kong
local json                             = require "cjson.safe"
local sts                              = require "kong.plugins.aws-request-signing.webidentity-sts-credentials"

local IAM_CREDENTIALS_CACHE_KEY_PATTERN = "plugin.aws-request-signing.iam_role_temp_creds.%s"
local GENERIC_STS_ERROR                 = "Error fetching STS credentials." ..
                                          " Enable 'return_aws_sts_error' in config for details."

local function handle_sts_error(err, return_sts_error)
  kong.log.err(err)
  if return_sts_error then
    local errJson = err:gsub("failed to get from node cache:", "")
    local resError = json.decode(errJson)
    if resError then
      return kong.response.exit(resError.sts_status, { message = resError.message, stsResponse = resError.sts_body })
    end
    return kong.response.exit(500, { message = errJson })
  end
  return kong.response.exit(401, { message = GENERIC_STS_ERROR })
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

local function get_iam_credentials(sts_conf, refresh, return_sts_error)
  local iam_role_cred_cache_key = string.format(IAM_CREDENTIALS_CACHE_KEY_PATTERN, sts_conf.RoleArn)

  if refresh then
    kong.log.debug("invalidated iam_role cache!")
    kong.cache:invalidate_local(iam_role_cred_cache_key)
  end

  local iam_role_credentials, err = kong.cache:get(
    iam_role_cred_cache_key,
    nil,
    sts.fetch_assume_role_credentials,
    sts_conf
  )

  if err then
    return handle_sts_error(err, return_sts_error)
  end

  ngx.update_time()
  if not iam_role_credentials
      or (ngx.now() + 60) > iam_role_credentials.expiration then
    kong.cache:invalidate_local(iam_role_cred_cache_key)
    iam_role_credentials, err = kong.cache:get(
      iam_role_cred_cache_key,
      nil,
      sts.fetch_assume_role_credentials,
      sts_conf
    )
    if err then
      return handle_sts_error(err, return_sts_error)
    end
    kong.log.debug("expiring key, invalidated iam_cache and fetched fresh credentials!")
  end
  return iam_role_credentials
end

return {
  retrieve_token = retrieve_token,
  get_iam_credentials = get_iam_credentials,
  handle_sts_error = handle_sts_error
}