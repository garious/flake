local Object = require "object"

local Heap = Object:new()


function Heap:initialize()
end

function Heap:put(obj, value)
   table.insert(self, {obj=obj, value=value})
end

-- Return the object with the least value. This is *not* optimal and
-- hopefully will be replaced with something optimized to timer user cases
-- (once we have timer use cases).
--
function Heap:minPos()
   if #self > 0 then
      local minpos = 1
      local minvalue = self[minpos].value
      for n = 2, #self do
         if self[n].value < minvalue then
            minpos = n
            minvalue = self[minpos].value
         end
      end
      return minpos
   end
end

function Heap:first()
   local n = self:minPos()
   if n then
      return self[n].obj
   end
end

function Heap:get()
   local n = self:minPos()
   if n then
      local obj = self[n].obj
      table.remove(self, n)
      return obj
   end
end

function Heap:remove(obj)
   for n = 1, #self do
      if rawequal(self[n].obj, obj) then
         table.remove(self, n)
         return obj
      end
   end
end


return Heap
