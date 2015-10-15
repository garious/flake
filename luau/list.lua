-- Immutable list operations

local object = require 'object'
local serialize = require 'serialize'

local M = object:new()

function M.eq(a,b)
   if type(a) == "table" and type(b) == "table" then
      for k,v in pairs(a) do
         if not M.eq(v, b[k]) then
            return false
         end
      end
      for k,v in pairs(b) do
         if a[k] == nil then
            return false
         end
      end
      return true
   end
   return a == b
end

function M.tostring(t)
   return serialize.serialize(t, nil, 's')
end

function M.clone(self)
   local t = M.empty(getmetatable(self))
   for k,v in pairs(self) do
      t[k] = v
   end
   return t
end

function M.append(a,b)
   local t = M.clone(a)
   for _,v in ipairs(b) do
      t[#t+1] = v
   end
   return t
end

function M.merge(a,b)
   local t = M.clone(a)
   for k,v in pairs(b) do
     t[k] = v
   end
   return t
end

M.__eq       = M.eq
M.__concat   = M.append
M.__tostring = M.tostring
M.__index    = M

function M:new(t)
   return setmetatable(t and M.clone(t) or {}, M)
end

function M.singleton(v)
   return setmetatable({v}, M)
end

function M.empty(mt)
   return mt and setmetatable({}, mt) or {}
end

function M.fromString(s)
   local t = M.new()
   for i=1,#s do
      t[i] = string.sub(s,i,i)
   end
   return t
end

function M:keys()
   local t = M.empty(getmetatable(self))
   for k,_ in pairs(self) do
      t[#t+1] = k
   end
   return t
end

function M:map(f)
   local t = M.empty(getmetatable(self))
   for k,v in pairs(self) do
      t[k] = f(v)
   end
   return t
end

function M:mapWithKeys(f)
   local t = M.empty(getmetatable(self))
   for k,v in pairs(self) do
      local v,k2 = f(v,k)
      t[k2 or k] = v
   end
   return t
end

function M:swap()
   return M.mapWithKeys(self, function(x,y) return y,x end)
end

function M:reverse()
   local t = M.empty(getmetatable(self))
   for i=#self,1,-1 do
      t[#t+1] = self[i]
   end
   return t
end

function M:filter(f)
   local t = M.empty(getmetatable(self))
   for i,v in ipairs(self) do
      if f(v,i) then
         t[#t+1] = v
      end
   end
   return t
end

-- partition(f) === filter(f), filter(not . f)
function M:partition(f)
   local mt = getmetatable(self)
   local good = M.empty(mt)
   local bad  = M.empty(mt)
   for k,v in ipairs(self) do
      if f(v,k) then
         good[#good+1] = v
      else
         bad[#bad+1] = v
      end
   end
   return good, bad
end

-- partitionWhile(f) === takeWhile(f), dropWhile(not . f)
function M:partitionWhile(f)
   local mt = getmetatable(self)
   local good = M.empty(mt)
   local bad  = M.empty(mt)
   local done = false
   for k,v in ipairs(self) do
      if not done and f(v,k) then
         good[#good+1] = v
      else
         done = true
         bad[#bad+1] = v
      end
   end
   return good, bad
end


-- Note: Functional programming languages typically pass the accumulator to first
-- parameter of the provided function, but in Lua we pass it to the second,
-- so that we can pass multiple accumulators efficiently.  If we were to pass
-- the accumulator to the left parameter, then the Lua implementation would
-- be forced to create an intermediary table to hold the accumulators and
-- the next list value and then unpack that into the provided function.
local function foldl(t, i, f, ...)
   if i == #t+1 then
      return ...
   else
      return foldl(t, i+1, f, f(t[i], ...))
   end
end

function M:foldFromLeft(f,...)
   return foldl(self,1,f,...)
end

local function foldr(t, i, f, ...)
   if i == 0 then
      return ...
   else
      return foldr(t, i-1, f, f(t[i], ...))
   end
end

function M:foldFromRight(f,...)
   return foldr(self,#self,f,...)
end

-- Use fold() to express that traversing left versus right doesn't matter.
function M:fold(f,...)
   return foldr(self,#self,f,...)
end


local function concat(x, y)
   return x .. y
end

function M:concat()
   local last = self[#self]
   if type(last) == "string" then
      -- table.concat() is far more efficient for strings
      return table.concat(self)
   elseif last == nil or type(last) == "table" then
      local mt = last and getmetatable(last)
      if mt and mt ~= M and mt.__concat then
         return M.foldFromRight(self, concat, '')
      else
         local t = M.empty(getmetatable(self))
         for _,u in ipairs(self) do
            for _,v in ipairs(u) do
               t[#t+1] = v
            end
         end
         return t
      end
   else
      error("error: cannot concat tables of type: " .. type(head))
   end
end

local function add(x, y) return x + y end
local function mul(x, y) return x * y end

function M:sum()     return M.fold(self, add, 0) end
function M:product() return M.fold(self, mul, 1) end

function M:concatMap(f)
   return M.concat( M.map(self, f) )
end

function M:sort(f)
   local t = M.clone(self)
   table.sort(t, f)
   return t
end

function M:find(x)
   for _,v in pairs(self) do
      if v == x then
          return v
      end
   end
   return nil
end

function M:union(t)
   local function notInLHS(x)
     return M.find(self, x) == nil
   end
   local t2 = M.filter(t, notInLHS)
   return M.append(self, t2)
end

function M:intersect(t)
   local function inRHS(x)
     return M.find(t, x) ~= nil
   end
   return M.filter(self, inRHS)
end

return M

