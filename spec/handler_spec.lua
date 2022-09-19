local realNgx = ngx
local authGuid = "29dfe875-f5a8-40bf-a7a1-ce13cb60b854" --- just a guid to check for in the test
local mock_request_headers = {
  ["some-header"] = "some value",
  ["authorization"] = "bearer " .. authGuid,
  ["x-authorization"] = "Bearer this value should not show up"
}

local mock_cache = {
  ["plugin.aws-request-signing.iam_role_temp_creds.valid"] = {
    ["expiration"] = 67,
    ["session_token"] = "bab2305f-0059-4f9f-a098-dbb84a44aeeb"
  },
  ["plugin.aws-request-signing.iam_role_temp_creds.expired"] = {
    ["expiration"] = 4,
    ["session_token"] = "5decbb76-914d-4435-9177-dc819c739648"
  }
}

-- Mock of sts
local fetch_aws_credentials = spy.new(function() end)

-- Mock of ngx
local ngx = {
  now = spy.new(function() return 5 end),
  var = realNgx.var,
  re = realNgx.re,
  update_time = realNgx.update_time
}

-- Mock of kong
local kong = {
  request = {
    get_headers = spy.new(function() return mock_request_headers end),
    set_headers = spy.new(function() end),
    get_raw_body = spy.new(function() end)
  },
  service = {
    request = {
      set_raw_body = spy.new(function() end)
    }
  },
  log = {
    err = spy.new(function() end),
    debug = spy.new(function() end)
  },
  cache = {
    invalidate_local = spy.new(function() end),
    get = spy.new(function(_tbl, val)
      return mock_cache[val]
    end)
  },
  status = 200
}

_G.fetch_aws_credentials = fetch_aws_credentials
_G.ngx = ngx
_G.kong = kong
_G._TEST = true -- tell scripts we're testing so it can export the public functions

local handler = require("kong.plugins.aws-request-signing.handler")

describe("retrieve_token_should", function()
  it("return_auth_token_from_correct_header", function()
    local returnedToken = handler._retrieve_token()
    assert.equal(authGuid, returnedToken)
  end)
  it("return_auth_token_from_correct_header_with_capital_B", function()
    mock_request_headers["authorization"] = "Bearer " .. authGuid
    local returnedToken = handler._retrieve_token()
    assert.equal(authGuid, returnedToken)
  end)
  it("return_nil_if_header_doesnt_contain_bearer", function()
    mock_request_headers["authorization"] = "Basic whatever"
    local returnedToken = handler._retrieve_token()
    assert.falsy(returnedToken)
  end)
  it("return_nil_if_header_doesnt_exist", function()
    mock_request_headers["authorization"] = nil
    local returnedToken = handler._retrieve_token()
    assert.falsy(returnedToken)
  end)
end)

describe("get_iam_credentials_should", function()
  local valid_sts_conf, expired_sts_conf

  setup(function()
    valid_sts_conf = {
      RoleArn = "valid",
      WebIdentityToken = authGuid,
      RoleSessionName = "roleSessionName",
    }
    expired_sts_conf = {
      RoleArn = "expired",
      WebIdentityToken = authGuid,
      RoleSessionName = "roleSessionName",
    }
  end)

  before_each(function()
    kong.cache.invalidate_local = spy.new(function() end) -- reset spy counter
  end)

  it("return_from_cache", function()
    local output = handler._get_iam_credentials(valid_sts_conf, false)
    assert.equal("bab2305f-0059-4f9f-a098-dbb84a44aeeb", output.session_token)
  end)
  it("not_invalidate_cache_if_token_isnt_expired", function()
    handler._get_iam_credentials(valid_sts_conf, false)
    assert.spy(kong.cache.invalidate_local).was.called(0)
  end)
  it("invalidate_cache_if_token_is_expired", function()
    handler._get_iam_credentials(expired_sts_conf, false)
    assert.spy(kong.cache.invalidate_local).was.called(1)
  end)
  it("invalidate_cache_if_refresh_is_passed", function()
    handler._get_iam_credentials(valid_sts_conf, true)
    assert.spy(kong.cache.invalidate_local).was.called(1)
  end)
  it("not_invalidate_cache_if_refresh_is_not_passed", function()
    handler._get_iam_credentials(valid_sts_conf, false)
    assert.spy(kong.cache.invalidate_local).was.called(0)
  end)
end)

