-- Configuration file for LuaCheck
-- see: https://luacheck.readthedocs.io/en/stable/
--
-- To run do: `luacheck .` from the repo

globals = {
    "_KONG",
    "kong",
    "ngx.IS_CLI",
    "ngx"
}
