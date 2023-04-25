local typedefs = require "kong.db.schema.typedefs"

return {
  name = "aws-request-signing",
  fields = {
    {
      -- this plugin will not be applied to consumers
      consumer = typedefs.no_consumer,
    },
    {
      -- this plugin will only run within Nginx HTTP module
      protocols = typedefs.protocols_http
    },
    { config = {
      type = "record",
      fields = {
        { aws_assume_role_arn = {
          type = "string",
          encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
          required = true,
        } },
        { aws_assume_role_name = {
          type = "string",
          encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
          required = true,
        } },
        { aws_region = {
          type = "string",
          required = true,
        } },
        { aws_service = {
          type = "string",
          required = true,
        } },
        { override_target_host = {
          type = "string"
        } },
        { override_target_port = {
          type = "number"
        } },
        { override_target_protocol = {
          type = "string",
              one_of = {
                "http",
                "https",
              },
        } },
        { return_aws_sts_error = {
          type = "boolean",
          required = true,
          default = false,
        } },
        }
      },
    }
  },
  entity_checks = {
  }
}
