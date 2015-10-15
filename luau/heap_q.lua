local qt = require "qtest"
local Heap = require "heap"

local eq = qt.eq


local h = Heap:new()

h:put("c", 3)
h:put("d", 4)
h:put("a", 1)
h:put("b", 2)


eq(h:remove("b"), "b")


eq(h:first(), "a")
eq(h:get(), "a")
eq(h:first(), "c")
eq(h:get(), "c")
eq(h:first(), "d")
eq(h:get(), "d")
eq(h:first(), nil)
eq(h:get(), nil)
eq(h:first(), nil)
