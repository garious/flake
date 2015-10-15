----------------------------------------------------------------
-- testobject.lua : Tests for object.lua
----------------------------------------------------------------
local qt = require "qtest"
local Object = require "object"

local tests = qt.tests

function tests.adopt()
   local a = { a = 1 }
   local b = { b = 2 }

   Object.adopt(a, b)

   assert(b.a == 1)
   assert(b.b == 2)
   assert(a.a == 1)
   assert(a.b == nil)
end

function tests.new()
   local a = Object:new()
   local b = a:new()

   a.a = 1
   b.b = 2
   assert(b.a == 1)
   assert(b.b == 2)
   assert(a.a == 1)
   assert(a.b == nil)
end

function tests.getParent()
   local a = Object:new()
   local b = Object:new()
   function Object:getName() return "Object" end
   function a:getName() return "a" end

   assert(a:getParent() == Object)
   assert(a:getName() == "a")
   assert(b:getName() == "Object")
   assert(a:getParent():getName() == "Object")
end


function tests.scenario1()
   local a = Object:new()

   -- Initialize()
end


return qt.runTests()

