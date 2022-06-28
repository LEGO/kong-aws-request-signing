local typedefs = require "kong.db.schema.typedefs"

return {
  name = "aws-webid-access",
  fields = {
    {
      -- this plugin will only be applied to Services
      consumer = typedefs.no_consumer,
    },
    {
      -- this plugin will only be applied to Services
      route = typedefs.no_route
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
          referenceable = true,
          required = true,
        } },
        { aws_assume_role_name = {
          type = "string",
          encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
          referenceable = true,
          required = true,
        } },
        { aws_region = {
          type = "string",
          required = true,
        } },
        { aws_service = {
          type = "string",
          required = true,
        } }
        }
      },
    }
  },
  entity_checks = {
  }
}
