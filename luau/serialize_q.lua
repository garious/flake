local qt = require "qtest"
local S = require "serialize"

---- orderedPairs

local orderedPairs = S.orderedPairs

local function top(t, o)
   local s = ""
   for k,v in orderedPairs(t) do
      s = s .. tostring(k) .. "=" .. tostring(v) .. ";"
   end
   return qt.eq(o, s)
end

top( {y="A", x="a", [5]="b", [false] = true, [true] = false, 9},
     "1=9;false=true;true=false;5=b;x=a;y=A;" )

---- serialize to function/string

local serialize = S.serialize

local function serTest(x)
   local tt = {}
   local function tw(x)
      table.insert(tt, x)
   end
   serialize(x, tw)
   local str = table.concat(tt)
   local x2 = assert(load("return " .. str))()
   qt._eq(x, x2, 2)

   -- no writer => return string
   local str2 = serialize(x)
   qt._eq(str, str2, 2)

   -- writer == table
   local t3 = {}
   local r = serialize(x, t3)
   qt._eq(str, table.concat(t3), 2)
end

serTest(1)
serTest("a")
serTest{"a",7,x="2",[9]={},["a-b"]=false}

-- inf, -inf, nan
serTest(1/0)
serTest(-1/0)
serTest(0/0)

---- serialize ordered

qt.eq( '{9,[false]=true,[true]=false,[5]="b",x="a",y="A"}',
       serialize({y="A", x="a", [5]="b", [false] = true, [true] = false, 9}, nil, "s") )


