-- interpreter.lua
--
-- This Lua chunk implements some of the behavior of the standard standalone
-- Lua interpreter.  Use it with cfromlua to generate a standalone
-- interpreter that has built-in modules (implemented in either Lua or C).
--
package.path = os.getenv("LUA_PATH") or ";?.lua;"
package.cpath = os.getenv("LUA_CPATH") or ";?.so;"
local progname = arg[0]
local interact = false
local execed = false
local loadstdin = false
local showver = false

local unpack = table.unpack or unpack
local load = loadstring or load

local version = _VERSION .. "/fromlua interpreter.lua"

local usagestr = [=[
_VER
usage: _PROG [options] [script [args]]
Options are:
   -e str    execute string 'str'
   -l lib    require package 'lib'
   -i        enter interactive mode after processing other arguments
   -v        show version information
   --        stop processing options
   -         execute stdin and stop handling options
]=]

local function usage()
   io.write( (usagestr:gsub("_[A-Z]+", {_PROG=progname, _VER=version})) )
   return 1
end

local function trace(err)
   local str = debug.traceback(err,2)
   -- chop off last six lines (C, preamble, interpreter.lua)
   return str:gsub("\n[^\n]*\n[^\n]*\n[^\n]*\n[^\n]*\n[^\n]*\n[^\n]*$", "")
end

-- process arguments

local an = #arg
local n = 1

local function getParam(a)
   if #a > 2 then
      return a:sub(3)
   end
   n = n + 1
   return arg[n]
end

while n <= an do
   local a = arg[n]
   if a == "-l" then
      n = n + 1
      require(arg[n])
   elseif a == "-i" then
      interact = true
   elseif a:match("^%-l") then
      require( getParam(a) )
   elseif a:match("^%-e") then
      local fn, err = load( getParam(a), "=(command line)")
      if not fn then
         print(progname..": "..err)
         return 1
      end
      fn()
      execed = true
   elseif a == "-v" then
      showver = true
      execed = true
   elseif a == "--" then
      n = n + 1
      break
   elseif a == "-" then
      loadstdin = true
      break
   elseif a:match("^%-") then
      return usage()
   else
      break
   end
   n = n + 1
end

-- shift arguments left (progname == arg[0])
for m = 0,an+n do
   arg[m-n] = arg[m]
end

-- exec script or stdin

local result = 0

if loadstdin or arg[0] then
   local fn, err
   if loadstdin then
      fn, err = load(io.read, "=stdin")
   else
      fn,err = loadfile(arg[0])
   end
  if not fn then
     print(progname..": "..err)
     return 1
  end
  local succ, err = xpcall(function () return fn(unpack(arg)) end, trace)
  if not succ then
     print(err)
     return 1
  end
  result = err
  execed = true
end

-- display version?

interact = interact or not execed
if showver or interact then
   print(version)
end

if not interact then
   return result
end

-- interactive mode

local function showResult(succ, ...)
   if select('#',...) >= 1 then
      print(...)
   end
end

local continued = ""
while true do
   io.write("> ")
   local a = io.read("*l")
   if not a or a:match(" *quit *") then
      break
   end
   a = continued .. a:gsub("^=", "return ")
   continued = ""
   local fn, err = load(a, "=stdin")
   if fn then
      -- pass results to another function, which can reliably deal with
      -- multiple return values using "...".  A table constructor --
      -- {xpcall(...)} -- might lose nil results.
      showResult(xpcall(fn,trace))
   elseif err and err:match("<eof>()") == #err then
      io.write(">")
      continued = a .. "\n"
   else
      print(err)
   end
end


return result
