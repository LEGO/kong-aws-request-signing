-- Configuration file for LuaCheck
-- see: https://luacheck.readthedocs.io/en/stable/
--
-- To run do: `luacheck .` from the repo

globals = {
    "kong",
    "ngx.IS_CLI",
    "ngx"
}
