-- object.lua

local Object = {}

-- Set o's parent to self
--   We use a lightweight, simple parenting strategy, as decribed in PiL:
--   metatable == metatable.__index == parent
function Object:adopt(o)
   rawset(self, "__index", self)
   setmetatable(o, self)
   return o
end

function Object:getParent()
   local p = getmetatable(self).__index
   return type(p) == "table" and p or nil
end

-- Create a new child of self
function Object:basicNew()
   return self:adopt{}
end

-- Create and initialize a new child
function Object:new(...)
   local o = self:basicNew()
   o:initialize(...)
   return o
end

function Object:initialize()
  -- nothing to do
end

return Object
