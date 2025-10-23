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
    {
      config = {
        type = "record",
        fields = {
          {
            aws_assume_role_arn = {
              type = "string",
              encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
              required = true,
            }
          },
          {
            aws_assume_role_name = {
              type = "string",
              encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
              required = true,
            }
          },
          {
            aws_region = {
              type = "string",
              required = true,
            }
          },
          {
            aws_service = {
              type = "string",
              required = true,
            }
          },
          {
            override_target_host = {
              type = "string",
              not_match = "^https?://"
            }
          },
          {
            override_target_port = {
              type = "number"
            }
          },
          {
            override_target_protocol = {
              type = "string",
              one_of = {
                "http",
                "https",
              },
            }
          },
          {
            use_altered_target = {
              type = "boolean",
              required = true,
              default = false,
              description =
                  "Instructs the plugin to use the context target if its host or port were altered "..
                  " (by other plugins) during the signing, bypassing the override_target_host "..
                  "and override_target_port parameters. Works by comparing the service target parameters"..
                  " with the context target parameters. Ignored if the target was not altered."
            }
          },
          {
            return_aws_sts_error = {
              type = "boolean",
              required = true,
              default = false,
            }
          },
          {
            sign_query = {
              type = "boolean",
              required = true,
              default = false,
            }
          },
          {
            auth_header = {
              type = "string",
              required = false,
            }
          },
          {
            preserve_auth_header = {
              type = "boolean",
              required = true,
              default = true,
            }
          },
          {
            preserve_auth_header_key = {
              type = "string",
              required = true,
              default = "x-authorization",
            }
          }
        }
      },
    }
  },
  entity_checks = {
  }
}
