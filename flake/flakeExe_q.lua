local xpfs = require 'xpfs'
local qtest = require 'qtest'
local process = require 'process'

local eq = qtest.eq

local flakeExe = arg[1]
print(flakeExe)

local function flake(args, stdin, env)
   local t = {flakeExe}
   for _, v in ipairs(args) do
     table.insert(t, v)
   end
   local code, stdout, stderr = process.readProcess(t, env, stdin)
   if code == nil then
     code = 0
   end
   return {
     stdout = stdout,
     stderr = stderr,
     code = code
   }
end

local function flakeGood(...)
   local out = flake(...)
   eq(out.code, 0)
   return out.stdout
end

local function flakeFail(...)
   local out = flake(...)
   eq(out.code, 1)
   local s, _ = out.stderr:gsub('^flake: ', '')
   return s
end

local outdir = os.getenv 'OUTDIR'

xpfs.mkdir(outdir)

-- Adversarial tests
eq(flakeFail{'bogus.lua'}, "Cannot find file or Lua module 'bogus.lua'.")
eq(flakeFail{'-C', 'bogus'}, "No such file or directory")
eq(flakeFail{'-C', outdir}, "Cannot find file or Lua module 'build.lua'.")

-- It is an error to set a field on a builder object
local buildFile = "require('flake').lift(function() end, 'foo')()[1] = 42"
assert(flakeFail({'-'}, buildFile):match 'setting a field on a builder object is not permitted')

-- Sunny day tests
eq(flakeGood({'-'}, 'print(123)'), '123')

local buildFile = [[
local flake = require 'flake'
local function foo()
end
local fooBuilder = flake.lift(foo, 'foo')
return fooBuilder()
]]
eq(flakeGood({'-'}, buildFile), '==> foo()\n--> nil')

--TODO:
--local buildFile = [[
--local flake = require 'flake'
--local function foo()
--  return 'fail'
--end
--local fooBuilder = flake.lift(foo, 'foo')
--return fooBuilder(123)
--]]
--eq(flakeFail({'-'}, buildFile), 'fail')

print 'passed!'
