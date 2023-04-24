-- Performs AWSv4 Signing
-- http://docs.aws.amazon.com/general/latest/gr/sigv4_signing.html
-- A modified version of https://github.com/Kong/kong/blob/master/kong/plugins/aws-lambda/v4.lua

-- BSD License
local resty_sha256 = require "resty.sha256"
local to_hex = require "resty.string".to_hex
-- MIT License
local pl_string = require "pl.stringx"
-- BSD 2-Clause License
local openssl_hmac = require "resty.openssl.hmac"

local ngx = ngx

local ALGORITHM = "AWS4-HMAC-SHA256"

local function url_encode(str)
  if str then
    str = str:gsub("\n", "\r\n")
    str = str:gsub("([^%w %-%_%.%~])",
        function(c)
          return string.format("%%%02X", string.byte(c))
        end)
    str = str:gsub(" ", "+")
  end
  return str
end

local function removeCharFromStart(str, char)
  if str:sub(1, #char) == char then
      return str:sub(#char+1)
  else
      return str
  end
end

local function hmac(secret, data)
  return openssl_hmac.new(secret, "sha256"):final(data)
end

local function hash(str)
  local sha256 = resty_sha256:new()
  sha256:update(str)
  return sha256:final()
end

local function percent_encode(char)
  return string.format("%%%02X", string.byte(char))
end

local function canonicalise_path(path, aws_service)
  local segments = {}
  for segment in path:gmatch("/([^/]*)") do
    if segment == "" or segment == "." then
      segments = segments -- do nothing and avoid lint
    elseif segment == " .. " then
      -- intentionally discards components at top level
      segments[#segments] = nil
    else
      local unescaped = ngx.unescape_uri(segment):gsub("[^%w%-%._~]",
      percent_encode)
      if aws_service == "lambda" then
        unescaped = url_encode(segment)
      end
      segments[#segments+1] = unescaped
    end
  end
  local len = #segments
  if len == 0 then
    return "/"
  end
  -- If there was a slash on the end, keep it there.
  if path:sub(-1, -1) == "/" then
    len = len + 1
    segments[len] = nil
  end
  segments[0] = ""
  kong.log.debug(table.concat(segments, "/", 0, len))
  return table.concat(segments, "/", 0, len)
end

local function canonicalise_query_string(query)
  local q = {}
  for key, val in query:gmatch("([^&=]+)=?([^&]*)") do
    key = ngx.unescape_uri(key):gsub("[^%w%-%._~]", percent_encode)
    val = ngx.unescape_uri(val):gsub("[^%w%-%._~]", percent_encode)
    q[#q+1] = key .. "=" .. val
  end
  table.sort(q)
  return table.concat(q, "&")
end

local function get_canonical_headers(headers)
  local canonical_headers, signed_headers do
    -- We structure this code in a way so that we only have to sort once.
    canonical_headers, signed_headers = {}, {}
    local i = 0
    for name, value in pairs(headers) do
      if value then -- ignore headers with 'false', they are used to override defaults
        i = i + 1
        local name_lower = name:lower()
        signed_headers[i] = name_lower
        canonical_headers[name_lower] = pl_string.strip(value)
      end
    end
    table.sort(signed_headers)
    for j=1, i do
      local name = signed_headers[j]
      local value = canonical_headers[name]
      canonical_headers[j] = name .. ":" .. value .. "\n"
    end
    signed_headers = table.concat(signed_headers, ";", 1, i)
    canonical_headers = table.concat(canonical_headers, nil, 1, i)
  end
  return {
    canonical_headers = canonical_headers,
    signed_headers = signed_headers
  }
end

local function derive_signing_key(kSecret, date, region, service)
  local kDate = hmac("AWS4" .. kSecret, date)
  local kRegion = hmac(kDate, region)
  local kService = hmac(kRegion, service)
  return hmac(kService, "aws4_request")
end

local function prepare_awsv4_request(opts)
  local region = opts.region
  local service = opts.service
  local request_method = opts.method
  local host = opts.host
  local canonicalURI = canonicalise_path(opts.path, service)


  local req_headers = opts.headers or {}
  local req_payload = opts.body
  local access_key = opts.access_key
  local secret_key = opts.secret_key

  local port = opts.port
  local timestamp = opts.timestamp or ngx.time()
  local req_date = os.date("!%Y%m%dT%H%M%SZ", timestamp)
  local date = os.date("!%Y%m%d", timestamp)

  local host_header do -- If the "standard" port is not in use, the port should be added to the Host header
    if port ~= 443 and port ~= 80 then
      host_header = string.format("%s:%d", host, port)
    else
      host_header = host
    end
  end

  req_headers["host"] = host_header

  if not opts.sign_query then
    req_headers["x-amz-date"] = req_date
    req_headers["x-amz-security-token"] = opts.session_token
    if service == "s3" then
      req_headers["x-amz-expires"] = "300"
      req_headers["x-amz-content-sha256"] = "UNSIGNED-PAYLOAD"
    end
  end

  local transformedHeaders = get_canonical_headers(req_headers)

  local credential_scope = date .. "/" .. region .. "/" .. service .. "/aws4_request"

  local expires = ""
  if service == "s3" then
    expires = "&X-Amz-Expires=300"
  end

  local req_query = opts.query

  if opts.sign_query then
    req_query = req_query .. "&X-Amz-Security-Token=" .. url_encode(opts.session_token)
    .. expires
    .. "&X-Amz-Date=" .. req_date
    .. "&X-Amz-Algorithm="..ALGORITHM
    .. "&X-Amz-Credential=" .. access_key .. "/" .. credential_scope
    .. "&X-Amz-SignedHeaders=" .. transformedHeaders.signed_headers
  else

  end

  req_query = removeCharFromStart(req_query, "&")

  local canonical_querystring = canonicalise_query_string(req_query)

  -- Task 1: Create a Canonical Request For Signature Version 4
  -- http://docs.aws.amazon.com/general/latest/gr/sigv4-create-canonical-request.html
  local bodyHash = to_hex(hash(req_payload or ""))
  if service == "s3" then
    bodyHash = "UNSIGNED-PAYLOAD"
  end

  local canonical_request =
    request_method .. '\n' ..
    canonicalURI .. '\n' ..
    (canonical_querystring or "") .. '\n' ..
    transformedHeaders.canonical_headers .. '\n' ..
    transformedHeaders.signed_headers .. '\n' ..
    bodyHash

  local hashed_canonical_request = to_hex(hash(canonical_request))

  -- Task 2: Create a String to Sign for Signature Version 4
  -- http://docs.aws.amazon.com/general/latest/gr/sigv4-create-string-to-sign.html

  local string_to_sign =
    ALGORITHM .. '\n' ..
    req_date .. '\n' ..
    credential_scope .. '\n' ..
    hashed_canonical_request

  -- Task 3: Calculate the AWS Signature Version 4
  -- http://docs.aws.amazon.com/general/latest/gr/sigv4-calculate-signature.html
  local signing_key = derive_signing_key(secret_key, date, region, service)

  local signature = to_hex(hmac(signing_key, string_to_sign))

  -- Task 4: Add the Signing Information to the Request
  -- http://docs.aws.amazon.com/general/latest/gr/sigv4-add-signature-to-request.html
  if opts.sign_query then
    req_query = req_query .. "&X-Amz-Signature=" .. signature
  else
    req_headers["authorization"] = ALGORITHM
    .. " Credential=" .. access_key .. "/" .. credential_scope
    .. ", SignedHeaders=" .. transformedHeaders.signed_headers
    .. ", Signature=" .. signature
  end

  return {
    headers = req_headers,
    query = req_query
  }
end

return prepare_awsv4_request