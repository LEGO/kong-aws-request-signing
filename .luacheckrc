-- Configuration file for LuaCheck
-- see: https://luacheck.readthedocs.io/en/stable/
--
-- To run do: `luacheck .` from the repo

globals = {
    "kong",
    "ngx.IS_CLI",
    "ngx",
    "_TEST"
}

ignore = {
    "212/self",  -- don't complain about functions not using their implicit self arguments
}
