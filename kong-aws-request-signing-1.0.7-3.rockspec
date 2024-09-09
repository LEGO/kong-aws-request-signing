local plugin_name = "aws-request-signing"
local package_name = "kong-" .. plugin_name
local package_version = "1.0.7"
local rockspec_revision = "3"

local github_account_name = "LEGO"
local github_repo_name = "kong-aws-request-signing"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git+https://github.com/"..github_account_name.."/"..github_repo_name..".git",
  branch = "main",
}


description = {
  summary = "Allow the secure use of AWS Lambdas as upstreams in Kong using Lambda URLs. Reduces the cost and complexity of your solution by bypassing AWS API Gateway.",
  homepage = "https://"..github_account_name..".github.io/"..github_repo_name,
  license = "Section 6 Modified Apache 2.0 https://github.com/LEGO/kong-aws-request-signing/blob/main/LICENSE",
}

dependencies = {
}


build = {
  type = "builtin",
  modules = {
    ["kong.plugins."..plugin_name..".handler"] = "kong/plugins/"..plugin_name.."/handler.lua",
    ["kong.plugins."..plugin_name..".sigv4"] = "kong/plugins/"..plugin_name.."/sigv4.lua",
    ["kong.plugins."..plugin_name..".webidentity-sts-credentials"] = "kong/plugins/"..plugin_name.."/webidentity-sts-credentials.lua",
    ["kong.plugins."..plugin_name..".schema"] = "kong/plugins/"..plugin_name.."/schema.lua",
  }
}
