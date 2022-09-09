local authGuid = "29dfe875-f5a8-40bf-a7a1-ce13cb60b854" --- just a guid to check for in the test
local mock_request_headers = {
  ["some-header"] = "some value",
  ["authorization"] = "bearer " .. authGuid,
  ["x-authorization"] = "Bearer this value should not show up"
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
  status = 200
}

_G.kong = kong
_G._TEST = true
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
