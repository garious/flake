-- write value of LUA_PATH to a file names in arg[1]

local p = assert(os.getenv("LUA_PATH"))
local f = assert(io.open(arg[1], "w"))

f:write("<" .. p .. ">")
f:close()
return 0
