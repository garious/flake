local Object = require "object"

local Queue = Object:new()


function Queue:initialize()
   -- items are in q[a...b-1]
   self.a = 1
   self.b = 1
   self.q = {}
end


-- Append to "back" end of queue
--
function Queue:put(value)
   local b, q = self.b, self.q

   q[b] = value
   self.b = b + 1
end


-- Remove from "front" end of queue
--
function Queue:get()
   local a, b, q = self.a, self.b, self.q

   if a < b then
      local value = q[a]
      q[a] = nil
      self.a = a+1
      return value
   end
end


function Queue:first()
   return self.q[self.a]
end


function Queue:prepend(value)
   local a, q = self.a, self.q

   a = a - 1
   q[a] = value
   self.a = a
end


function Queue:remove(value)
   local a, b, q = self.a, self.b, self.q

   for n = a, b-1 do
      if value == q[n] then
         for i = n, b-2 do
            q[i] = q[i+1]
         end
         q[b-1] = nil
         self.b = b-1
         return value
      end
   end
end


function Queue:length()
   return self.b - self.a
end


return Queue
