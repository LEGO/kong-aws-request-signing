local helpers = require "spec.helpers"
local schema_def = require("kong.plugins.aws-request-signing.schema")

describe("schema", function()
  it("accepts aws_assume_role_arn that ends with aws_assume_role_name", function()
    local ok, err = helpers.validate_plugin_config_schema({
      aws_assume_role_arn = "arn:aws:iam::123456789012:role/my-role",
      aws_assume_role_name = "my-role",
      aws_region = "us-east-1",
      aws_service = "execute-api",
    }, schema_def)
    assert.is_truthy(ok)
    assert.is_nil(err)
  end)

  it("rejects aws_assume_role_arn that does not end with aws_assume_role_name", function()
    local ok, err = helpers.validate_plugin_config_schema({
      aws_assume_role_arn = "arn:aws:iam::123456789012:role/other-role",
      aws_assume_role_name = "my-role",
      aws_region = "us-east-1",
      aws_service = "execute-api",
    }, schema_def)
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  it("accepts config with aws_account_id instead of aws_assume_role_arn", function()
    local ok, err = helpers.validate_plugin_config_schema({
      aws_account_id = "123456789012",
      aws_assume_role_name = "my-role",
      aws_region = "us-east-1",
      aws_service = "execute-api",
    }, schema_def)
    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
end)
