local realNgx = ngx
local match = require("luassert.match")
local say = require("say")

-- Register custom "has_fields" matcher for partial table matching in spy assertions
say:set("assertion.has_fields.positive", "Expected table to contain fields:\n%s")
say:set("assertion.has_fields.negative", "Expected table to NOT contain fields:\n%s")
assert:register("matcher", "has_fields", function(_, arguments, _)
  local expected = arguments[1]
  return function(actual)
    if type(actual) ~= "table" then return false end
    for k, v in pairs(expected) do
      if type(v) == "table" and type(actual[k]) == "table" then
        for kk, vv in pairs(v) do
          if actual[k][kk] ~= vv then return false end
        end
      else
        if actual[k] ~= v then return false end
      end
    end
    return true
  end
end)

-- ─── Helpers ───────────────────────────────────────────────────────────────────

local function build_conf(overrides)
  local conf = {
    aws_assume_role_arn = "arn:aws:iam::123456789012:role/TestRole",
    aws_assume_role_name = "TestRole",
    aws_region = "us-east-1",
    aws_service = "execute-api",
    auth_header = "authorization",
    preserve_auth_header = true,
    preserve_auth_header_key = "x-authorization",
    override_target_host = nil,
    override_target_port = nil,
    override_target_protocol = nil,
    use_altered_target = false,
    return_aws_sts_error = false,
    sign_query = false,
    aws_account_id = nil,
  }
  if overrides then
    for k, v in pairs(overrides) do
      conf[k] = v
    end
  end
  return conf
end

local function build_mock_iam_credentials()
  return {
    access_key = "AKIAIOSFODNN7EXAMPLE",
    secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    session_token = "FwoGZXIvYXdzEBYaDH7GZXample",
  }
end

local function build_signed_request()
  return {
    headers = {
      host = "target.example.com",
      -- luacheck: max line length 200
      authorization = "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20260511/us-east-1/execute-api/aws4_request, SignedHeaders=host;x-amz-date, Signature=abc123",
      ["x-amz-date"] = "20260511T000000Z",
      ["x-amz-security-token"] = "FwoGZXIvYXdzEBYaDH7GZXample",
    },
    query = "signed=true",
  }
end

-- ─── Mock infrastructure ───────────────────────────────────────────────────────

local mock_request_headers
local mock_service
local mock_balancer_data
local mock_raw_body
local mock_get_body_err
local mock_iam_credentials
local mock_signed_request
local mock_sigv4_err

local ngx_re_match = realNgx.re.match

local ngx = {
  now = function() return 100 end,
  var = { upstream_uri = "/v1/resource" },
  re = { match = function(...) return ngx_re_match(...) end },
  update_time = realNgx.update_time,
  unescape_uri = realNgx.unescape_uri,
  ctx = {},
}

local kong

local function reset_mocks()
  mock_request_headers = {
    ["authorization"] = "Bearer my-jwt-token-12345",
    ["content-type"] = "application/json",
    ["content-length"] = "42",
  }
  mock_service = { host = "original.example.com", port = 443 }
  mock_balancer_data = { host = "original.example.com", port = 443 }
  mock_raw_body = '{"key":"value"}'
  mock_get_body_err = nil
  mock_iam_credentials = build_mock_iam_credentials()
  mock_signed_request = build_signed_request()
  mock_sigv4_err = nil

  ngx.ctx = { balancer_data = mock_balancer_data }

  kong = {
    router = {
      get_service = spy.new(function() return mock_service end),
    },
    request = {
      get_headers = spy.new(function() return mock_request_headers end),
      get_raw_body = spy.new(function() return mock_raw_body, mock_get_body_err end),
      get_method = spy.new(function() return "POST" end),
      get_raw_query = spy.new(function() return "foo=bar" end),
    },
    service = {
      request = {
        set_headers = spy.new(function() end),
        clear_header = spy.new(function() end),
        set_scheme = spy.new(function() end),
        set_raw_query = spy.new(function() end),
      },
      set_target = spy.new(function() end),
    },
    response = {
      exit = spy.new(function(_, _)
      end),
    },
    log = {
      err = spy.new(function() end),
      notice = spy.new(function() end),
      debug = spy.new(function() end),
    },
    cache = {
      get = spy.new(function(_, _, _, _, _)
        return mock_iam_credentials
      end),
      invalidate_local = spy.new(function() end),
    },
  }

  _G.ngx = ngx
  _G.kong = kong
end

-- ─── Require with fresh state ──────────────────────────────────────────────────

local handler
local mock_sigv4_fn
local mock_util

local function reload_handler()
  -- clear cached modules
  package.loaded["kong.plugins.aws-request-signing.handler"] = nil
  package.loaded["kong.plugins.aws-request-signing.sigv4"] = nil
  package.loaded["kong.plugins.aws-request-signing.util"] = nil

  -- mock sigv4
  mock_sigv4_fn = spy.new(function(_)
    if mock_sigv4_err then
      return nil, mock_sigv4_err
    end
    return mock_signed_request, nil
  end)
  package.loaded["kong.plugins.aws-request-signing.sigv4"] = mock_sigv4_fn

  -- mock util
  mock_util = {
    retrieve_token = spy.new(function(header_value)
      -- use real ngx.re.match for token extraction
      if header_value then
        if type(header_value) == "table" then
          header_value = header_value[1]
        end
        local captures = ngx_re_match(header_value, [[ \s* Bearer \s+ (.+) ]], "joxi", nil)
        if captures then
          return captures[1]
        end
      end
      return nil
    end),
    get_iam_credentials = spy.new(function(_, _, _)
      return mock_iam_credentials
    end),
  }
  package.loaded["kong.plugins.aws-request-signing.util"] = mock_util

  handler = require("kong.plugins.aws-request-signing.handler")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- ZOMBIES: Zero, One, Many, Boundaries, Interfaces, Exceptions, Simple/Scenarios
-- ═══════════════════════════════════════════════════════════════════════════════

describe("handler.access()", function()

  before_each(function()
    reset_mocks()
    reload_handler()
  end)

  -- ─── Z: Zero ──────────────────────────────────────────────────────────────────

  describe("[Zero]", function()

    it("exits 500 when service is nil", function()
      kong.router.get_service = spy.new(function() return nil end)
      reload_handler()

      handler:access(build_conf())

      assert.spy(kong.response.exit).was.called(1)
      assert.spy(kong.response.exit).was.called_with(500, { message = "The plugin must be bound to a service!" })
      assert.spy(kong.log.err).was.called(1)
    end)

    it("returns early (skips signing) when auth header is missing", function()
      mock_request_headers = { ["content-type"] = "application/json" }
      kong.request.get_headers = spy.new(function() return mock_request_headers end)
      reload_handler()

      handler:access(build_conf())

      assert.spy(kong.log.notice).was.called(1)
      assert.spy(mock_sigv4_fn).was_not.called()
      assert.spy(kong.response.exit).was_not.called()
    end)

    it("returns early when custom auth header is missing", function()
      mock_request_headers = { ["authorization"] = "Bearer token" }
      kong.request.get_headers = spy.new(function() return mock_request_headers end)
      reload_handler()

      handler:access(build_conf({ auth_header = "x-custom-auth" }))

      assert.spy(kong.log.notice).was.called(1)
      assert.spy(mock_sigv4_fn).was_not.called()
    end)

    it("handles empty body (nil raw body) with error", function()
      mock_raw_body = nil
      mock_get_body_err = "body too large"
      kong.request.get_raw_body = spy.new(function() return mock_raw_body, mock_get_body_err end)
      reload_handler()

      handler:access(build_conf())

      assert.spy(kong.response.exit).was.called(1)
      assert.spy(kong.response.exit).was
      .called_with(400, { message = "Request body exceeds size limit and cannot be used by plugins." })
    end)

    it("does not set headers when auth header value is nil (auth_header key absent)", function()
      mock_request_headers = {}
      kong.request.get_headers = spy.new(function() return mock_request_headers end)
      reload_handler()

      handler:access(build_conf())

      assert.spy(kong.service.request.set_headers).was_not.called()
    end)
  end)

  -- ─── O: One (happy path, single request) ──────────────────────────────────────

  describe("[One]", function()

    it("signs a standard request successfully", function()
      handler:access(build_conf())

      assert.spy(kong.service.request.clear_header).was.called(1)
      assert.spy(kong.service.request.clear_header).was.called_with("authorization")
      assert.spy(mock_util.retrieve_token).was.called(1)
      assert.spy(mock_util.retrieve_token).was.called_with("Bearer my-jwt-token-12345")
      assert.spy(mock_util.get_iam_credentials).was.called(1)
      assert.spy(mock_sigv4_fn).was.called(1)
      -- set_headers called twice: once preserve original auth, once signed headers
      assert.spy(kong.service.request.set_headers).was.called(2)
      assert.spy(kong.service.request.set_raw_query).was.called(1)
      assert.spy(kong.service.request.set_raw_query).was.called_with("signed=true")
      assert.spy(kong.response.exit).was_not.called()
    end)

    it("preserves auth header to configured key", function()
      handler:access(build_conf({ preserve_auth_header = true, preserve_auth_header_key = "x-original-auth" }))

      -- set_headers called twice: once for preserve, once for signed headers
      assert.spy(kong.service.request.set_headers).was.called(2)
    end)

    it("does not preserve auth header when preserve_auth_header is false", function()
      handler:access(build_conf({ preserve_auth_header = false }))

      -- set_headers called once: only for signed headers
      assert.spy(kong.service.request.set_headers).was.called(1)
      assert.spy(kong.service.request.set_headers).was.called_with(mock_signed_request.headers)
    end)

    it("passes correct sigv4 opts", function()
      handler:access(build_conf())

      assert.spy(mock_sigv4_fn).was.called(1)
      assert.spy(mock_sigv4_fn).was.called_with({
        region = "us-east-1",
        service = "execute-api",
        method = "POST",
        body = '{"key":"value"}',
        path = "/v1/resource",
        host = "original.example.com",
        port = 443,
        query = "foo=bar",
        access_key = "AKIAIOSFODNN7EXAMPLE",
        secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        session_token = "FwoGZXIvYXdzEBYaDH7GZXample",
        sign_query = false,
        headers = {
          host = "original.example.com",
          ["content-length"] = "42",
          ["content-type"] = "application/json",
        },
      })
    end)

    it("passes sign_query=true when configured", function()
      handler:access(build_conf({ sign_query = true }))

      assert.spy(mock_sigv4_fn).was.called(1)
      assert.spy(mock_sigv4_fn).was.called_with(match.has_fields({ sign_query = true }))
    end)

    it("constructs RoleArn from account_id and role_name when arn not provided", function()
      -- must explicitly nil out aws_assume_role_arn after build_conf
      local conf = build_conf({
        aws_account_id = "987654321012",
        aws_assume_role_name = "MyRole"
      })
      conf.aws_assume_role_arn = nil
      handler:access(conf)

      assert.spy(mock_util.get_iam_credentials).was.called(1)
      assert.spy(mock_util.get_iam_credentials).was.called_with(
        {
          RoleArn = "arn:aws:iam::987654321012:role/MyRole",
          WebIdentityToken = "my-jwt-token-12345",
          RoleSessionName = "MyRole",
        },
        nil,
        false
      )
    end)

    it("uses aws_assume_role_arn directly when provided", function()
      handler:access(build_conf({
        aws_assume_role_arn = "arn:aws:iam::111111111111:role/CustomRole",
        aws_assume_role_name = "CustomRole",
      }))

      assert.spy(mock_util.get_iam_credentials).was.called(1)
      assert.spy(mock_util.get_iam_credentials).was.called_with(
        {
          RoleArn = "arn:aws:iam::111111111111:role/CustomRole",
          WebIdentityToken = "my-jwt-token-12345",
          RoleSessionName = "CustomRole",
        },
        nil,
        false
      )
    end)

    it("passes x-sts-refresh header to get_iam_credentials", function()
      mock_request_headers["x-sts-refresh"] = "true"
      kong.request.get_headers = spy.new(function() return mock_request_headers end)
      reload_handler()

      handler:access(build_conf())

      assert.spy(mock_util.get_iam_credentials).was.called(1)
      assert.spy(mock_util.get_iam_credentials).was.called_with(
        match.is_table(),
        "true",
        false
      )
    end)

    it("passes nil for x-sts-refresh when header absent", function()
      handler:access(build_conf())

      assert.spy(mock_util.get_iam_credentials).was.called(1)
      assert.spy(mock_util.get_iam_credentials).was.called_with(
        match.is_table(),
        nil,
        false
      )
    end)

    it("passes return_aws_sts_error config to get_iam_credentials", function()
      handler:access(build_conf({ return_aws_sts_error = true }))

      assert.spy(mock_util.get_iam_credentials).was.called(1)
      assert.spy(mock_util.get_iam_credentials).was.called_with(
        match.is_table(),
        nil,
        true
      )
    end)
  end)

  -- ─── M: Many / Multiple scenarios ─────────────────────────────────────────────

  describe("[Many]", function()

    it("handles request with no content-type and no content-length", function()
      mock_request_headers = { ["authorization"] = "Bearer token123" }
      kong.request.get_headers = spy.new(function() return mock_request_headers end)
      reload_handler()

      handler:access(build_conf())

      assert.spy(mock_sigv4_fn).was.called(1)
      assert.spy(mock_sigv4_fn).was.called_with(match.has_fields({
        headers = { host = "original.example.com" }
      }))
    end)

    it("uses default auth_header 'authorization' when conf.auth_header is nil", function()
      handler:access(build_conf({ auth_header = nil }))

      -- should still find the authorization header and proceed
      assert.spy(mock_sigv4_fn).was.called(1)
    end)
  end)

  -- ─── B: Boundaries ────────────────────────────────────────────────────────────

  describe("[Boundaries]", function()

    it("handles empty string body", function()
      mock_raw_body = ""
      kong.request.get_raw_body = spy.new(function() return mock_raw_body, nil end)
      reload_handler()

      handler:access(build_conf())

      assert.spy(mock_sigv4_fn).was.called(1)
      assert.spy(mock_sigv4_fn).was.called_with(match.has_fields({ body = "" }))
      assert.spy(kong.response.exit).was_not.called()
    end)

    it("exits 400 when get_raw_body returns error even with non-nil body", function()
      mock_raw_body = nil
      mock_get_body_err = "request body in temp file not supported"
      kong.request.get_raw_body = spy.new(function() return mock_raw_body, mock_get_body_err end)
      reload_handler()

      handler:access(build_conf())

      assert.spy(kong.response.exit).was.called(1)
      assert.spy(kong.response.exit).was
      .called_with(400, { message = "Request body exceeds size limit and cannot be used by plugins." })
    end)

    it("exits 400 when body is nil without explicit error", function()
      mock_raw_body = nil
      mock_get_body_err = nil
      kong.request.get_raw_body = spy.new(function() return nil, nil end)
      reload_handler()

      handler:access(build_conf())

      assert.spy(kong.response.exit).was.called(1)
      assert.spy(kong.log.err).was.called(1)
    end)
  end)

  -- ─── I: Interfaces (target override, protocol, altered target) ─────────────────

  describe("[Interfaces - target override]", function()

    it("overrides target host when configured", function()
      handler:access(build_conf({ override_target_host = "override.example.com" }))

      assert.spy(kong.service.set_target).was.called(1)
      assert.spy(kong.service.set_target).was.called_with("override.example.com", 443)
      assert.spy(mock_sigv4_fn).was.called_with(match.has_fields({ host = "override.example.com" }))
    end)

    it("overrides target port when configured", function()
      handler:access(build_conf({ override_target_port = 8443 }))

      assert.spy(kong.service.set_target).was.called(1)
      assert.spy(kong.service.set_target).was.called_with("original.example.com", 8443)
      assert.spy(mock_sigv4_fn).was.called_with(match.has_fields({ port = 8443 }))
    end)

    it("overrides both host and port", function()
      handler:access(build_conf({ override_target_host = "new.host.com", override_target_port = 9090 }))

      assert.spy(kong.service.set_target).was.called(1)
      assert.spy(kong.service.set_target).was.called_with("new.host.com", 9090)
    end)

    it("does not call set_target when no override configured", function()
      handler:access(build_conf())

      assert.spy(kong.service.set_target).was_not.called()
    end)

    it("sets scheme when override_target_protocol configured", function()
      handler:access(build_conf({ override_target_protocol = "https" }))

      assert.spy(kong.service.request.set_scheme).was.called(1)
      assert.spy(kong.service.request.set_scheme).was.called_with("https")
    end)

    it("does not set scheme when override_target_protocol is nil", function()
      handler:access(build_conf({ override_target_protocol = nil }))

      assert.spy(kong.service.request.set_scheme).was_not.called()
    end)

    it("sets scheme to http", function()
      handler:access(build_conf({ override_target_protocol = "http" }))

      assert.spy(kong.service.request.set_scheme).was.called_with("http")
    end)
  end)

  describe("[Interfaces - use_altered_target]", function()

    it("skips override when target was altered and use_altered_target=true", function()
      -- simulate altered target: balancer differs from service
      mock_balancer_data = { host = "altered.example.com", port = 8080 }
      ngx.ctx = { balancer_data = mock_balancer_data }
      reload_handler()

      handler:access(build_conf({
        use_altered_target = true,
        override_target_host = "should-not-use.example.com",
        override_target_port = 9999,
      }))

      assert.spy(kong.service.set_target).was_not.called()
      -- signs with balancer target instead
      assert.spy(mock_sigv4_fn).was.called_with(match.has_fields({
        host = "altered.example.com",
        port = 8080,
      }))
    end)

    it("applies override when target NOT altered even with use_altered_target=true", function()
      -- balancer matches service = not altered
      mock_balancer_data = { host = "original.example.com", port = 443 }
      ngx.ctx = { balancer_data = mock_balancer_data }
      reload_handler()

      handler:access(build_conf({
        use_altered_target = true,
        override_target_host = "override.example.com",
      }))

      assert.spy(kong.service.set_target).was.called(1)
      assert.spy(kong.service.set_target).was.called_with("override.example.com", 443)
    end)

    it("applies override when use_altered_target=false even if target altered", function()
      mock_balancer_data = { host = "altered.example.com", port = 8080 }
      ngx.ctx = { balancer_data = mock_balancer_data }
      reload_handler()

      handler:access(build_conf({
        use_altered_target = false,
        override_target_host = "override.example.com",
      }))

      assert.spy(kong.service.set_target).was.called(1)
      assert.spy(kong.service.set_target).was.called_with("override.example.com", 8080)
    end)

    it("detects alteration when only host differs", function()
      mock_balancer_data = { host = "different.example.com", port = 443 }
      ngx.ctx = { balancer_data = mock_balancer_data }
      reload_handler()

      handler:access(build_conf({
        use_altered_target = true,
        override_target_host = "ignored.example.com",
      }))

      assert.spy(kong.service.set_target).was_not.called()
    end)

    it("detects alteration when only port differs", function()
      mock_balancer_data = { host = "original.example.com", port = 9999 }
      ngx.ctx = { balancer_data = mock_balancer_data }
      reload_handler()

      handler:access(build_conf({
        use_altered_target = true,
        override_target_port = 1111,
      }))

      assert.spy(kong.service.set_target).was_not.called()
    end)
  end)

  describe("[Interfaces - preserve_auth_header]", function()

    it("preserves auth header to default key x-authorization", function()
      handler:access(build_conf({ preserve_auth_header = true }))

      assert.spy(kong.service.request.set_headers).was.called(2)
      assert.spy(kong.service.request.set_headers).was.called_with(
        { ["x-authorization"] = "Bearer my-jwt-token-12345" }
      )
    end)

    it("preserves auth header to custom key", function()
      handler:access(build_conf({
        preserve_auth_header = true,
        preserve_auth_header_key = "x-original-token",
      }))

      assert.spy(kong.service.request.set_headers).was.called(2)
      assert.spy(kong.service.request.set_headers).was.called_with(
        { ["x-original-token"] = "Bearer my-jwt-token-12345" }
      )
    end)

    it("clears auth header regardless of preserve setting", function()
      handler:access(build_conf({ preserve_auth_header = false }))

      assert.spy(kong.service.request.clear_header).was.called(1)
      assert.spy(kong.service.request.clear_header).was.called_with("authorization")
    end)

    it("clears custom auth header key", function()
      mock_request_headers = { ["x-my-auth"] = "Bearer token" }
      kong.request.get_headers = spy.new(function() return mock_request_headers end)
      reload_handler()

      handler:access(build_conf({ auth_header = "x-my-auth", preserve_auth_header = false }))

      assert.spy(kong.service.request.clear_header).was.called(1)
      assert.spy(kong.service.request.clear_header).was.called_with("x-my-auth")
    end)
  end)

  -- ─── E: Exceptions ────────────────────────────────────────────────────────────

  describe("[Exceptions]", function()

    it("exits 500 when sigv4 returns error", function()
      mock_sigv4_err = "Invalid credentials"
      reload_handler()

      handler:access(build_conf())

      assert.spy(kong.response.exit).was.called(1)
      assert.spy(kong.response.exit).was.called_with(500, { message = "Invalid credentials" })
      assert.spy(kong.log.err).was.called(1)
    end)

    it("exits 500 when sigv4 returns nil without error", function()
      mock_sigv4_fn = spy.new(function() return nil, nil end)
      package.loaded["kong.plugins.aws-request-signing.sigv4"] = mock_sigv4_fn
      package.loaded["kong.plugins.aws-request-signing.handler"] = nil
      handler = require("kong.plugins.aws-request-signing.handler")

      handler:access(build_conf())

      assert.spy(kong.response.exit).was.called(1)
      assert.spy(kong.response.exit).was.called_with(500, { message = "Unable to SIGV4 the request!" })
    end)

    it("exits 500 with custom sigv4 error message", function()
      mock_sigv4_err = "Region mismatch: got us-west-2 expected us-east-1"
      reload_handler()

      handler:access(build_conf())

      assert.spy(kong.response.exit).was
      .called_with(500, { message = "Region mismatch: got us-west-2 expected us-east-1" })
    end)

    it("exits 400 when body error occurs", function()
      mock_raw_body = nil
      mock_get_body_err = "request body in temp file not supported"
      kong.request.get_raw_body = spy.new(function() return nil, mock_get_body_err end)
      reload_handler()

      handler:access(build_conf())

      assert.spy(kong.log.err).was.called(1)
      assert.spy(kong.response.exit).was.called(1)
      assert.spy(kong.response.exit).was
      .called_with(400, { message = "Request body exceeds size limit and cannot be used by plugins." })
    end)

    it("errors when get_iam_credentials returns nil (handler does not guard nil credentials)", function()
      mock_iam_credentials = nil
      mock_util.get_iam_credentials = spy.new(function()
        return nil
      end)
      package.loaded["kong.plugins.aws-request-signing.util"] = mock_util
      package.loaded["kong.plugins.aws-request-signing.handler"] = nil
      handler = require("kong.plugins.aws-request-signing.handler")

      assert.has_error(function()
        handler:access(build_conf())
      end)
    end)
  end)

  -- ─── S: Simple scenarios / Smoke tests ─────────────────────────────────────────

  describe("[Simple]", function()

    it("has correct PRIORITY", function()
      assert.equal(15, handler.PRIORITY)
    end)

    it("has correct VERSION", function()
      assert.equal("1.1.0", handler.VERSION)
    end)

    it("upstream_headers include host from balancer", function()
      handler:access(build_conf())

      assert.spy(mock_sigv4_fn).was.called(1)
      assert.spy(mock_sigv4_fn).was.called_with(match.has_fields({
        headers = { host = "original.example.com" }
      }))
    end)

    it("upstream_headers include content-length from request", function()
      handler:access(build_conf())

      assert.spy(mock_sigv4_fn).was.called(1)
      assert.spy(mock_sigv4_fn).was.called_with(match.has_fields({
        headers = { ["content-length"] = "42" }
      }))
    end)

    it("upstream_headers include content-type from request", function()
      handler:access(build_conf())

      assert.spy(mock_sigv4_fn).was.called(1)
      assert.spy(mock_sigv4_fn).was.called_with(match.has_fields({
        headers = { ["content-type"] = "application/json" }
      }))
    end)

    it("uses ngx.var.upstream_uri as path", function()
      ngx.var.upstream_uri = "/custom/path/resource"
      reload_handler()

      handler:access(build_conf())

      assert.spy(mock_sigv4_fn).was.called(1)
      assert.spy(mock_sigv4_fn).was.called_with(match.has_fields({ path = "/custom/path/resource" }))
    end)

    it("uses kong.request.get_method() result", function()
      kong.request.get_method = spy.new(function() return "PUT" end)
      reload_handler()

      handler:access(build_conf())

      assert.spy(mock_sigv4_fn).was.called(1)
      assert.spy(mock_sigv4_fn).was.called_with(match.has_fields({ method = "PUT" }))
    end)

    it("uses kong.request.get_raw_query() result", function()
      kong.request.get_raw_query = spy.new(function() return "a=1&b=2" end)
      reload_handler()

      handler:access(build_conf())

      assert.spy(mock_sigv4_fn).was.called(1)
      assert.spy(mock_sigv4_fn).was.called_with(match.has_fields({ query = "a=1&b=2" }))
    end)

    it("GET request without body still signs", function()
      mock_raw_body = ""
      kong.request.get_raw_body = spy.new(function() return mock_raw_body, nil end)
      kong.request.get_method = spy.new(function() return "GET" end)
      mock_request_headers = { ["authorization"] = "Bearer token" }
      kong.request.get_headers = spy.new(function() return mock_request_headers end)
      reload_handler()

      handler:access(build_conf({ preserve_auth_header = false }))

      assert.spy(mock_sigv4_fn).was.called(1)
      assert.spy(kong.response.exit).was_not.called()
    end)

    it("STS conf uses RoleSessionName from conf.aws_assume_role_name", function()
      handler:access(build_conf({ aws_assume_role_name = "SessionRole" }))

      assert.spy(mock_util.get_iam_credentials).was.called(1)
      assert.spy(mock_util.get_iam_credentials).was.called_with(
        match.has_fields({ RoleSessionName = "SessionRole" }),
        nil,
        false
      )
    end)

    it("STS conf WebIdentityToken from token extraction", function()
      handler:access(build_conf())

      assert.spy(mock_util.get_iam_credentials).was.called(1)
      assert.spy(mock_util.get_iam_credentials).was.called_with(
        match.has_fields({ WebIdentityToken = "my-jwt-token-12345" }),
        nil,
        false
      )
    end)
  end)
end)
