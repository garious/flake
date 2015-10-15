--
-- An immutable list library for Lua
--
-- No functions in this library modify their input and every function
-- returns a value. Any function can be used as an ordinary function or
-- as a method.
--
local List = require "list"

--
-- eq()
--
-- Compares of a table's values.  Returns true if all equal.
--
assert(List.eq(         {},   {} ))
assert(List.eq( List:new(),   {} ))
assert(List.eq( List:new{},   {} ))
assert(List.eq( List:new(),   List:new() ))
assert(List.eq( List:new{},   List:new() ))

local L = function(t) return List:new(t) end
assert(List.eq(  {1},    {1} ))
assert(List.eq( L{1},    {1} ))
assert(List.eq(  {1},   L{1} ))
assert(List.eq( L{1},   L{1} ))

assert(List.eq( L{{1},{2}}, L{{1},{2}} ))

assert( List:new() == List:new() )     -- Metatables on both

--
-- clone()
--
-- clone() is identical to new() except that:
--   1) clone() requires an input table
--   2) clone() will not add a metatable if the input
--      table does not have one.
--
assert(getmetatable(List.clone{})           == nil)
assert(getmetatable(List:new{})             == List)
assert(getmetatable(List.clone(List:new{})) == List)

--
-- singleton()
--
assert( List.singleton(1) == L{1}  )

assert( L{1}   == L{1}  )
assert( L{1}   ~= L{2}  )
assert( L{1}   ~= L{1,2})
assert( L{1,2} ~= L{1})

--
-- map()
--
-- Create a list using the values of another.
--
-- The user-defined function accepts a value and the key, and returns
-- a value which 'map' will use to set the key.
--
-- Optionally, the user-defined function can return a key.  If so,
-- map will set that key instead.
--
local function inc(x) return x + 1 end

assert(List.eq( List.map({1,2,3}, inc),    {2,3,4}))
assert(List.eq( List.map({1,2,3}, inc),   L{2,3,4}))

assert(L{1,2,3}:map(inc):eq{2,3,4})
assert(L{1,2,3}:map(inc):eq(L{2,3,4}))

assert(L(List.map({1,2,3}, inc)) == L{2,3,4})
assert(L{1,2,3}:map(inc)         == L{2,3,4})

-- Using objects means the returned tables have metatables.
-- If using tables as arrays, you should never have a problem,
-- but if using tables as maps, there can be a naming conflict
-- between keys and method names.  If so, the key is used and its
-- value is returned.
assert(({1,2,3}).map               == nil)
assert(L{1,2,3}.map                == List.map) -- List:new adds metatable
assert(L{1,2,3}:map(inc).map       == List.map) -- Inherit metatable
assert(List.map( {1,2,3}, inc).map == nil)      -- No metatable to inherit
assert(List.map(L{1,2,3}, inc).map == List.map) -- Inherit metatable
assert(({abc=3}).map               == nil)
assert(L{abc=3}.map                == List.map)
assert(L{abc=3}:map(inc)           == L{abc=4}) -- Can map() key-value pairs
assert(({map=3}).map               == 3)        -- ...
assert(L{map=3}.map                == 3)        -- ...unless key is 'map'
assert(L(List.map( {map=3}, inc))  == L{map=4}) -- Use function instead.
assert(L(List.map(L{map=3}, inc))  == L{map=4}) -- Function inherits meta
assert(  List.map(L{map=3}, inc)   == L{map=4}) -- No need to call 'new' again.

-- verify map() is not implemented with mapWithKeys()
-- gsub() returns 2 values, which mapWithKeys() would use as the new key.
local function subx(s) return s:gsub("x","X") end

assert(L{"x","x"}:map(subx)         == L{"X","X"})
assert(L{"x","x"}:mapWithKeys(subx) == L{"X"})

--
-- filter()
--
local function gt0(x) return x > 0 end
local function gt1(x) return x > 1 end
local function gt2(x) return x > 2 end
local function gt3(x) return x > 3 end

assert(L{1,2,3}:filter(gt0)     == L{1,2,3})
assert(L{1,2,3}:filter(gt1)     ==   L{2,3})
assert(L{1,2,3}:filter(gt2)     ==     L{3})
assert(L{1,2,3}:filter(gt3)     ==      L{})

local function idxgt2(_,x) return x > 2 end
assert(L{4,5,6}:filter(idxgt2)  ==     L{6})

--
-- partition()
--
assert(L{L{1,2,3}:partition(gt1)} == L{{2,3},{1}})

-- same as filter() when you ignore the second return value
assert(L{1,2,3}:partition(gt1) == L{1,2,3}:filter(gt1))

--
-- partitionWhile()
--
assert(L{L{3,2,1}:partitionWhile(gt0)} == L{{3,2,1}, {}})
assert(L{L{3,2,1}:partitionWhile(gt1)} == L{{3,2},  {1}})
assert(L{L{3,2,1}:partitionWhile(gt2)} == L{{3},  {2,1}})
assert(L{L{3,2,1}:partitionWhile(gt3)} == L{{}, {3,2,1}})

--
-- folds
--

local function add(x,y) return x+y end

-- If list is empty, accumulator is returned.
assert( L{}:foldFromLeft( add, 1) == 1)
assert( L{}:foldFromRight(add, 1) == 1)
assert( L{}:fold(         add, 1) == 1)

-- Can implement sum() with any fold, because add() commutes.
assert( L{1,2,3}:foldFromLeft(  add, 0) == 6)
assert( L{1,2,3}:foldFromRight( add, 0) == 6)
assert( L{1,2,3}:fold(          add, 0) == 6)

-- applications of fold().  sum(), product() and concat()
assert( L{2,3,4}:sum()           == 9)
assert( L{2,3,4}:product()       == 24)
assert( L{'a','b','c'}:concat()  == 'abc')
assert( L{{1},{2},{3}}:concat()  == L{1,2,3})

-- Each fold*() can accept or return multiple parameters
local function addAndCount(a,b,cnt) return a+b, cnt+1 end

assert(L{1,2,3}:foldFromRight(addAndCount, 0, 0), L{6, 3})
assert(L{1,2,3}:foldFromLeft( addAndCount, 0, 0), L{6, 3})
assert(L{1,2,3}:fold(         addAndCount, 0, 0), L{6, 3})


--
-- append()
--
assert(L(List.append({1}, {2,3}))  == L{1,2,3})
assert(L{1} .. L{2,3}              == L{1,2,3})
assert(L{1} ..  {2,3}              == L{1,2,3})
assert(L{1} ..  {}                 == L{1})

--
-- merge()
--
assert(L(List.merge({a=1,b=2}, {a=2}))  == L{a=2,b=2})
assert(L(List.merge({1}, {2,3}))        == L{2,3})

--
-- concat()
--
assert(L(List.concat{})            == L{})
assert(L(List.concat{{1}})         == L{1})
assert(L(List.concat{{1},{2},{3}}) == L{1,2,3})
assert(L{{1},{2},{3}}:concat()     == L{1,2,3})

--
-- tostring()
--
assert(tostring(L{1,2,3})       == '{1,2,3}')
assert(L{1,2,3}:tostring()      == '{1,2,3}')
assert(tostring(L{1,2,{3}})     == '{1,2,{3}}')
assert(tostring(L{'1','2','3'}) == '{"1","2","3"}')
assert(tostring(L{a=1})         == '{a=1}')
assert(tostring(L{1,2,a=3})     == '{1,2,a=3}')
assert(tostring(L{_a=1})        == '{_a=1}')
assert(tostring(L{['a.b']=1})   == '{["a.b"]=1}')

-- -- keys() and sort()
--
assert(L{a=1,b=2}:keys():sort() == L{'a','b'})

--
-- swap()
--
assert(L{a=1,b=2}:swap()        == L{'a','b'})

--
-- reverse()
--
assert(L{}:reverse()                == L{})
assert(L{1,2,3}:reverse()           == L{3,2,1})
assert(L{1,2,3}:reverse():reverse() == L{1,2,3})

--
-- find()
--
assert(L{1,2,3}:find(2)             == 2)
assert(L{1,2,3}:find(0)             == nil)
assert(L{a=1,b=2}:find(2)           == 2)

--
-- union()
--
assert(L{1,2,3}:union(L{})          == L{1,2,3})
assert(L{1,2,3}:union(L{1,2,3})     == L{1,2,3})
assert(L{1,2}:union(L{2,3})         == L{1,2,3})
assert(L{1,2}:union(L{2,2,3})       == L{1,2,3})
assert(L{1,2,2}:union(L{2,3})       == L{1,2,2,3})

--
-- intersect()
--
assert(L{1,2,3}:intersect(L{})      == L{})
assert(L{1,2,3}:intersect(L{1,2,3}) == L{1,2,3})
assert(L{1,2}:intersect(L{2,3})     == L{2})
assert(L{1,2}:intersect(L{2,2,3})   == L{2})
assert(L{1,2,2}:intersect(L{2,3})   == L{2,2})

--
-- Fun with strings
--
local S = List.fromString
local f = List.singleton
local function bang(s) return s .. '!' end
assert(S"abc"                                  == L{'a','b','c'})
assert(S"abc":append(S"")                      == L{'a','b','c'})
assert(S"abc":append(S"def")                   == L{'a','b','c','d','e','f'})
assert(S"abc":reverse()                        == L{'c','b','a'})
assert(S"abc":concat()                         == 'abc')
assert(S"abc":map(f)                           == L{{'a'},{'b'},{'c'}})
assert(S"abc":concatMap(f)                     == L{'a','b','c'})
assert(S"abc":concatMap(S)                     == L{'a','b','c'})
assert(S"abc":concatMap(f):concat()            == 'abc')
assert(S"abc":map(bang)                        == L{'a!','b!','c!'})
assert(S"abc":map(bang):concat()               == 'a!b!c!')

--
-- toy box
--
local function unique(t) return t:swap():keys() end
assert(unique(L{2,2,3}):sort() == L{2,3})
assert(unique(S"Greg":map(string.lower)):sort():concat() == "egr")
assert(unique(S(string.lower"Greg")):sort():concat()     == "egr")


local function findIndices(db, xs)
   local is = db:swap()
   return xs:map(function(v) return is[v] end)
end

local function findEach(db, xs)
   return findIndices(db, xs):map(function(v) return db[v] end)
end

local function findEach2(db, xs)
   local vs = db:mapWithKeys(function(v) return v,v end)
   return xs:map(function(v) return vs[v] end)
end

assert(findIndices(L{4,5,6,7}, L{5,6}) == L{2,3})
assert(findEach(   L{4,5,6,7}, L{5,6}) == L{5,6})
assert(findEach2(  L{4,5,6,7}, L{5,6}) == L{5,6})

