local qt = require "qtest"
local getopts = require "getopts"

local function matches(str, pat)
   local t = {}
   for m in str:gmatch(pat) do
      table.insert(t, m)
   end
   return t
end

function qt.tests.parseOpts()
   local function e(t,s)
      return qt.eq(t, getopts.parseOpts(s))
   end

   e({["-a"]={name="a",type=""}}, "-a")
   e({["-a"]={name="a",type="=*"},["-b"]={name="b",type=""}}, "-a=* -b")
   e({["--a-b"]={name="a-b",type="="},["-a"]={name="a-b",type="="}}, "--a-b/-a=")
end

function qt.tests.read()
   local function errx(str)
      return 0, str
   end
   local function e(t,argstr,s,e)
      local a = matches(argstr, "[^ ]+")
      return qt.eq(t, {getopts.read(a,s,e or errx)})
   end

   e({{},{a=1}},                       "-a",          "-a")
   e({{},{a=1}},                       "--aa",         "-a/--aa")
   e({{},{a=2}},                       "-a --aa",     "-a/--aa")
   e({{},{a="x"}},                     "-a x",        "-a/--aa=")
   e({{},{aa="x"}},                    "-a x",        "--aa/-a=")
   e({{},{a="x"}},                     "-a x",        "-a=")
   e({{},{a={"x","y"}}},               "--a x --a=y", "--a=*")
   e({{},{a="x"}},                     "-a x",         "-a=")
   e({{"-a"},{}},                      "-- -a",       "-a")
   e({0,"Unrecognized option: -a=x"},  "-a=x",        "-a=*")
   e({0,"Missing argument to -a"},     "-a",          "-a=")
   e({{},{}},                          "-a",          "-a=", function() end)     --continue on error
   e({{},{}},                          "-b",          "-a/--aa", function() end) --continue on error
   e({{},{a=1}},                       "--aa -b",     "-a/--aa", function() end) --continue on error
end

return qt.runTests()
