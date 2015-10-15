-- qtest.lua: unit test helpers
--
-- When loaded, qtest will trap accesses to the global table.
--
--   qt.eq(a, b)                    -- assert a is equivalent to b
--   qt.same(a, b)                  -- assert rawequal(a, b)
--   qt.match(str, pat, [level)     -- assert str:match(pat)
--   qt.assert(value, msg, [level]) -- assert cond is truthy
--   qt.printf()                    -- implements '%Q'
--

local debug = require "debug"


local qt = {}


function qt.fail(trace)
   print(trace)
   os.exit(1)
end


-- Terminate the program and display a backtrace.  We construct the
-- backtrace ourselves so we don't depend on the default message handler
-- (e.g. this works even inside a pcall).
--
function qt.error(msg, level)
   level = tonumber(level) or 1
   msg = msg or "ERROR"

   -- `error(msg,level)` prepends "FILE:LINE: " to `msg`.  The `level`
   -- parameter identifies the stack frame for "FILE:LINE:".  The default
   -- message handler typically appends a traceback, which includes *all*
   -- functions on the stack, including those in qtest.lua.

   -- Here we re-create something similar, except that we hide all stack
   -- frames that are in qtest.lua. They do not appear in the traceback, and
   -- `level` is the count of stack frames outside of qtest.lua.

   local qlevel = 2
   while debug.getinfo(qlevel, "S").short_src:match("qtest%.lua$") do
      qlevel = qlevel + 1
   end

   local i = debug.getinfo(qlevel + level - 1) or { short_src="?", currentline="?" }
   local err = "ERROR: " .. i.short_src .. ":" .. i.currentline .. ": " .. msg

   if debug.printf then
      debug.printf(err)
      -- debug.pause(2)
   end
   return qt.fail(debug.traceback(err, qlevel))
end


-- If `value` is falsy, raise error.
--
function qt.assert(value, msg, level)
   if not value then
      return qt.error(msg, level)
   end
   return value
end


-- Trap attempts to read or write undefined global variables

local mt_G = {}
local allowWrite = {
   -- these legacy modules assign globals
   lpeg = true,
   re = true,
}
local allowRead = {
   loadstring = true   -- this was defined in lua 5.1
}

-- warn of un-intentional use of globals
function mt_G:__newindex(key, value)
   qt.assert(allowWrite[key], "Write to undefined global: " .. tostring(key))
   return rawset(self,key,value)
end

function mt_G:__index(key)
   qt.assert(allowRead[key], "Read of undefined global: " .. tostring(key))
   return nil
end

setmetatable(_G, mt_G)


-- Shortcut for interactive mode:  require("qtest").G()
--
function qt.G()
   setmetatable(_G, nil)    -- enable globals
   _G.qt = qt               -- make 'qtest' available as 'qt'
end


-- if s is a valid lua identifier, return it.  Else return false.
local function identifier(s)
   return type(s) == "string" and s:match("^[%a_][_%w]*$")
end

-- describe: Return a string that describes a value.
--
--  * Result length can be truncated for readability.
--
--  * Table keys are sorted so the results are predictable and can be used
--    in assertions.
--
--  * Optional 'prefix' requests multiline representation of tables and
--    provides the string to use for indenting generated lines.
--
--  * See qtest_q.lua for examples.
--
local function describe(x, visited, indent)
   visited = visited or {level=1}
   local s

   if type(x) == "number" or
      type(x) == "boolean" or
      type(x) == "nil" then
      s = tostring(x)
   elseif type(x) == "string" then
      s = string.format("%q", x)
      s = s:gsub("\\\n", "\\n")
   elseif visited[x] then
      s = "@" .. (visited.level-visited[x]-1)
   elseif type(x) == "table" then
      visited[x] = visited.level
      visited.level = visited.level + 1

      local t, keys, names = {}, {}, {}
      t.insert = table.insert

      for k,v in ipairs(x) do
         t:insert(describe(v, visited, indent))
         names[k] = "visited"
      end

      -- sort printable names of keys that were not in ipairs()
      for k,v in pairs(x) do
         if not names[k] then
            table.insert(keys, k)
            names[k] = identifier(k) or "["..describe(k, visited).."]"
         end
      end
      table.sort(keys, function (a,b) return names[a] < names[b] end)
      for _,k in ipairs(keys) do
         t:insert(names[k] .. "=" .. describe(x[k], visited, indent))
      end

      if indent and t[1] then
         local prefix = indent:rep(visited.level - 2)
         local subprefix = prefix .. indent
         s = "{\n" .. subprefix .. table.concat(t, ",\n" .. subprefix) .. "\n" .. prefix .. "}"
      else
         s = "{" .. table.concat(t,",") .. "}"
      end

      visited.level = visited.level - 1
      visited[x] = false
   else
      s = "<"..tostring(x)..">"
   end

   return s
end


qt.describe = describe


function qt.dump(name, value)
   print(name .. " = " .. describe(value, nil, ""))
end


-- qt.format() : like string.format + support for "%Q" which represents the
--     output of qt.describe()
--
function qt.format(fmt, ...)
   local t = {...}
   local ndx = 0

   local function repl(s)
      if s ~= "%%" then
         ndx = ndx + 1
         if s == "%Q" then
            t[ndx] = describe(t[ndx])
            return "%s"
         end
      end
   end
   fmt = fmt:gsub("%%.", repl)

   return string.format(fmt, table.unpack(t))
end

-- qt.printf()
--
function qt.printf(...)
   io.write(qt.format(...))
end

function qt.fprintf(f, ...)
   f:write(qt.format(...))
end


-- Assertions

-- An analysis of the usage of qtest assertions in Pakman + Smark sources
-- (2802 assertions in 15K lines of code, plus 9K lines of unit tests):
--
--     11 : test for equality, not equivalence
--    502 : test for equivalence, not equality
--   2192 : test for equality or equivalence (they are the same
--          for all types other than tables).
--     97 : search for pattern in string
--
-- As a result, `eq` tests for equivalence; `same` tests for strict
-- equality.


local function showAB(a, b, msg)
   if debug.log then
      debug.printf("%s", msg)
      debug.log(a)
      debug.log(b)
   end
   return string.format("%s\n   A: %s \n   B: %s",
                        msg,
                        describe(a),
                        describe(b))
end


local function checkArgs(name, cnt, ...)
   local n = select('#', ...)
   if cnt ~= n then
      return qt.error(name .. " saw " .. n .. " arguments; expected " .. cnt)
   end
end


function qt._eq(a, b, level)
   if not rawequal(a, b) and describe(a) ~= describe(b) then
      return qt.error(showAB(a, b, "Values not equivalent:"), level)
   end
end


-- Assert that `a` is equivalent to `b`. Show diagnostic and terminate
-- program otherwise.
--
function qt.eq(...)
   checkArgs('qtest.eq', 2, ...)
   return qt._eq(...)
end


-- Assert `a` == `b`. Show diagnostic and terminate program otherwise.
--
function qt.same(...)
   checkArgs('qtest.same', 2, ...)
   local a, b = ...
   if not rawequal(a, b) then
      return qt.error(showAB(a, b, "Values not identical:"))
   end
end


-- Assert that `pattern` matches `str`
--
function qt.match(str, pattern, level)
   qt.assert(type(str) == "string", "Arg 1 must be string")
   qt.assert(type(pattern) == "string", "Arg 2 must be string")
   qt.assert(level == nil or type(level) == "number", "Arg 3 must be nil or a number")

   local results = table.pack(str:match(pattern))
   if not results[1] then
      return qt.error(qt.format("\nExpected: %Q\n      in: %Q\n", pattern, str), level)
   end
   return table.unpack(results, 1, results.n)
end


-- trace(namestr, func)  -->  ftraced
--
-- Returned function behaves like func, but prints out inputs and outputs.
--
-- `namestr` is the function name, optionally followed by a format
-- specifiers for arguments (in parens) and/or return values (after "->").
-- Use qt.format patterns for format specifiers, or constant strings to
-- ignore the values.
--
-- If func is a table, func[function_name] will be used as the input function.
--
-- Example:
--
--     > function sum(a,...) return a and a+sum(...) or 0 end
--     > sum = qt.trace("sum",sum)
--     > sum(5,4)
--     sum{5,4}
--        sum{4}
--           sum{}
--           --> {0}
--        --> {4}
--     --> {9}
--
--     > qt.trace("Method(_,%3.2f) --> _,%s", Class)
--     > obj:method(1.1)
--     method(_,1.1)
--     --> _,nil

local tlvl = 0
function qt.trace(funcname,func)
   local name, argspec, rvspec = funcname:match("(.-)%((.-)%) *%-*>? *(.*)$")
   name = name or funcname
   local fn = (type(func) == "table" and func[name]) or func

   local function describeArgs(spec, ...)
      spec = spec or ""
      local str,fmt = ""
      for ndx = 1, select('#',...) do
         local value = select(ndx, ...)
         fmt, spec = spec:match("([^,]*)%,?(.*)")
         if fmt:sub(1,1) == "." then
            value = type(value)~="table" and "-undef-" or value[fmt:sub(2)]
            str = str .. ",{" .. fmt .. "=" .. qt.describe(value) .. "}"
         else
            str = str .. "," .. qt.format((fmt=="" and "%Q" or fmt),value)
         end
      end
      return str:sub(2), {...}
   end

   local function tfn(...)
      local i = string.rep("   ",tlvl)
      -- print args
      qt.printf("%s%s(%s)\n", i, name, describeArgs(argspec,...))
      tlvl = tlvl + 1
      local desc, res = describeArgs(rvspec, fn(...))
      qt.printf("%s--> %s\n", i, desc)
      tlvl = tlvl - 1
      return table.unpack(res)
   end

   if type(func) == "table" then
      func[name] = tfn
   end
   return tfn
end


-- Load a Lua sorce file, returning its return value *and* the values of
-- specified local variables.
--
--   locals = array of variable names
--
-- Returns: mod, localValues
--    mod = the value returned by the source file
--    localValues = name -> value, for each name listed in `locals`,
--           and the corresponding value when the module returned
--
function qt.load(file, locals)
   locals = locals or {}
   local f = io.open(file, "r")
   local txt
   if f then
      local txt = f:read("*a")

      -- find last "return"
      local posRet
      for pos in txt:gmatch("[^%w]()return[^%w]") do
         posRet = pos
      end

      if posRet then
         -- make sure this is really the end of the file
         local func, err = load(txt:sub(posRet))
         if not func then
            posRet = nil
         end
      end

      if posRet then
         local t = {}
         for _,var in ipairs(locals) do
            table.insert(t, var .. "=" .. var)
         end
         local ret = "return {" .. table.concat(t, ",") .. "},"
         local a = txt:sub(1,posRet-1) .. ret .. txt:sub(posRet+7)
         local func, err = load(a, "@" .. file)
         if func then
            local values, mod = func()
            return mod, values
         end
      end

      -- see if original text generates an error
      local succ, err0 = load(txt, "@"..file)
      if not succ then
         error("\n\t"..err0, 0)
      end
      error("qt.load: file does not return a value: " .. file)
   end
   error("qt.load: could not find file " .. tostring(file))
end


local function getlocal(lvl, name)
   for n = 1, 999 do
      local varname, value = debug.getlocal(lvl+1, n)
      if name == varname then
         return n, value
      end
   end
end


-- Display variable name and value
--
function qt.logvar(name)
   local ndx, value = getlocal(2, name)
   if ndx then
      return qt.printf("%s = %Q\n", name, value)
   end
   qt.printf("%s = -undefined-\n", name)
end


-- Trace function with given name
--
function qt.tracevar(name)
   local ndx, value = getlocal(2, name:match("[^%(]*"))
   if ndx then
      return debug.setlocal(2, ndx, qt.trace(name, value))
   end
   qt.printf("%s = -undefined-\n", name)
end


-- qt.runTests([name]) : Runs a set of previously defined tests.
--
-- Usage:
--
--    function qt.tests.test1() ... end
--    function qt.tests.test2() ... end
--    ...
--    return qt.runTests()
--
-- The benefit of using `qt.tests` and `qt.runTests()` -- versus simply
-- performing the tests in your main chunk -- is that a user can easily
-- specify a subset of the tests when iterating edit/test cycles.
--
--    $ mytest='test1 test7' make
--
-- The following flags can also be specified in the environment variable:
--
--    -v     : verbose mode; print name of each test executed.
--    -pass  : succeed without running run any tests.
--
function qt.runTests(name)
   local function ifVar(name)
      return (os.getenv(name) or ""):match("[^%s].*")
   end

   name = name or arg[0]:match("([^/]*)%.lua$")
   local spec = name and ifVar(name) or ifVar("qtest") or ""

   local namedTests, anyNamed, verbose = {}, false, false

   for w in spec:gmatch("[^%s]+") do
      if w == "-v" then
         verbose = true
      elseif w == "-pass" then
         return 0
      else
         assert(not w:match("^%-"), "Bad runTest spec")
         anyNamed = true
         namedTests[w] = true
      end
   end

   local incomplete = false
   for ndx,name in ipairs(qt.tests) do
      if not anyNamed or namedTests[name] then
         local fn = qt.tests[-ndx]
         if verbose then print(name) end
         fn()
      else
         incomplete = true
      end
   end

   if incomplete then
      -- do not treat as a success
      print("!!! ran only selected tests: " .. spec)
      return 99
   end

   if name and verbose then
      print(name .. " OK")
   end
   return 0
end


qt.tests = {}

local mt_tests = {}
function mt_tests:__newindex(k,v)
   local n = #self + 1
   rawset(self, n, k)
   rawset(self, -n, v)
end
setmetatable(qt.tests, mt_tests)


return qt
