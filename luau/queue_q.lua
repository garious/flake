local qt = require "qtest"
local Q = require "queue"

local eq = qt.eq

local a = Q:new()

eq(a:get(), nil)

-- put/get: empty -> non-empty -> empty

a:put(1)
eq(a:get(), 1)
eq(a:length(), 0)
a:put(1)
eq(a:length(), 1)
eq(a:get(), 1)
eq(a:length(), 0)

-- remove from start and from end

a:put(1)
a:put(2)
eq(a:remove(1), 1)
eq(a:get(), 2)
eq(a:length(), 0)

a:put(1)
a:put(2)
eq(a:remove(2), 2)
a:put(9)
eq(a:get(), 1)
eq(a:get(), 9)
eq(a:length(), 0)


-- append, prepend, and remove

a:put(1)
a:put(2)
a:put(3)
eq(a:length(), 3)

a:prepend(5)
a:put(4)
a:remove(3)

eq(a:length(), 4)

-- first & get

eq(a:first(), 5)
eq(a:get(), 5)
eq(a:get(), 1)
eq(a:get(), 2)
eq(a:first(), 4)
eq(a:get(), 4)
eq(a:get(), nil)
eq(a:first(), nil)
eq(a:length(), 0)

