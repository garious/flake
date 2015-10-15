local qt = require "qtest"

local testCount = 0

function qt.tests.describe()
   testCount = testCount + 1

   local function exd(a,...)
      local s = qt.describe(...)
      if a ~= s then
         print(a, "~=", s)
         error("assertion failed", 2)
      end
   end

   -- primitive types

   exd( '"abc"',    'abc' )
   exd( '"a\\"b"',  'a"b' )
   exd( '12',       12 )
   exd( 'true',     true )
   exd( 'false',    false )
   exd( 'nil',      nil )

   if not string.match( qt.describe(tostring), "<function.*>") then
      error("did not match function")
   end

   -- tables

   exd( '{1,2}', {1,2} )
   exd( '{1,2,[4]=true,a=3}',  {a=3,1,2,[4]=true} )

   -- table recursion
   local t = {} ; t[1] = t ; t[2] = {t}
   exd( '{@0,{@1}}', t)

   -- prefix
   assert( qt.describe({{1,2},3}, nil, "  ") ==
              "{\n  {\n    1,\n    2\n  },\n  3\n}")
end


local function expectFail(f, ...)
   local errmsg = nil

   local qa = qt.fail
   function qt.fail(msg) errmsg = msg end

   f(...)

   qt.fail = qa

   -- qt.fail was called?
   assert(type(errmsg) == "string")

   -- check error message format

   if not errmsg:match("traceback:\n\tqtest_q.lua:") then
      print( ("Error message:\n" .. errmsg):gsub("\n", "\n | "))
      error("Cluttered traceback", 2)
   end
end


function qt.tests.eq()
   testCount = testCount + 1

   qt.eq(true, true)
   qt.eq(1, 1)
   qt.eq({}, {})
   qt.eq('a', 'a')

   expectFail(qt.eq, 1, 2)
   expectFail(qt.eq, 1, "1")
   expectFail(qt.eq, true, "true")
   expectFail(qt.eq, {a=1}, {b=1})
   expectFail(qt.eq, function () end, function () return 1 end)
   expectFail(qt.eq, 1, 2, 3)  -- too many args
   expectFail(qt.eq, nil)      -- too few args
end


function qt.tests.same()
   testCount = testCount + 1
   local t = {}

   qt.same(1, 1)
   qt.same(nil, nil)
   qt.same(t, t)

   expectFail(qt.same, 1, 2)
   expectFail(qt.same, {}, {})
   expectFail(qt.same, nil)       -- not enough args
   expectFail(qt.same, 1, 1, 1)   -- too many args
end


function qt.tests.match()
   testCount = testCount + 1

   qt.match("abc", "b")
   qt.match("abc", ".")

   expectFail(qt.match, "b", "abc")
end


-- qt.load


local loadTestSrc = [[
local a = 1
local function f()
   return a
end
local b = 2
return {
  f = f,
  x = 2
}
]]

local function writeFile(name, data)
   local f = assert(io.open(name, "w"))
   f:write(data)
   f:close()
end

function qt.tests.load()
   testCount = testCount + 1

   local workdir = assert(os.getenv("OUTDIR"))
   local fname = workdir .. "/qtest_q_ml.lua"

   writeFile(fname, loadTestSrc)

   -- load module (success case)

   local lm, ll = qt.load(fname, {"f", "a", "b"})

   qt.eq("function", type(lm.f))
   qt.eq(lm.f, ll.f)
   qt.eq(1, ll.a)
   qt.eq(2, ll.b)
   qt.eq(ll.a, ll.f())

   -- error handling

   local m, err = pcall(function ()
                      return qt.load("DOESNOTEXIST", {"a", "b"})
                   end)

   qt.eq(false, m)
   qt.match(err, "could not find file DOESNOTEXIST")

end


assert(qt.runTests() == 0)

-- make sure qtest ran all the tests
qt.eq(testCount, 5)

