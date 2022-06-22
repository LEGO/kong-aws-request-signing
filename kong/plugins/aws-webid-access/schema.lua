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
        { timeout = {
          type = "number",
          required = true,
          default = 60000,
        } },
        { keepalive = {
          type = "number",
          required = true,
          default = 60000,
        } },
        { log_type = {
          type = "string",
          required = true,
          default = "Tail",
          one_of = { "Tail", "None" }
        } },
        { unhandled_status = {
          type = "integer",
          between = { 100, 999 },
        } },
        { forward_request_method = {
          type = "boolean",
          default = true,
        } },
        { forward_request_uri = {
          type = "boolean",
          default = true,
        } },
        { forward_request_headers = {
          type = "boolean",
          default = true,
        } },
        { forward_request_body = {
          type = "boolean",
          default = true,
        } },
        { skip_large_bodies = {
          type = "boolean",
          default = false,
        } },
        { base64_encode_body = {
          type = "boolean",
          default = false,
        } },
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
        } }
        }
      },
    }
  },
  entity_checks = {
  }
}
