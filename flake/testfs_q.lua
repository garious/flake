local testfs   = require 'testfs'
local lfsu     = require 'lfsu'

local tmp = assert(os.getenv 'OUTDIR', 'OUTDIR not set')

lfsu.mkdir_p(tmp)
lfsu.write(tmp .. '/a.c', 'foo\n')
lfsu.write(tmp .. '/b.c', 'foobar\n')

-- Assert tmp contains exactly a.c and b.c
assert(testfs.match(tmp, {'a.c', 'b.c'}))
assert(testfs.match(tmp, {['a.c'] = true, ['b.c'] = true}))

-- Assert tmp contains at least a.c
assert(testfs.match(tmp, {'a.c'}, true))

-- Assert tmp contains a.c and b.c and that their contents are exactly 'foo\n' and 'foobar\n'.
assert(testfs.match(tmp, {['a.c'] = 'foo\n', ['b.c'] = 'foobar\n'}))

-- Assert tmp contains at least a.c and its contents is exactly 'foo\n'
assert(testfs.match(tmp, {['a.c'] = 'foo\n'}, true))

-- Assert tmp contains a.c and b.c and that their contents each include the word 'foo'
local function hasfoo(s)
   return s:find('foo') ~= nil
end
assert(testfs.match(tmp, {['a.c'] = hasfoo,  ['b.c'] = hasfoo}))

local ok, err = testfs.match(tmp,   {'a.c'})
assert(not ok)
assert(err == "unexpected file 'b.c' found in '" .. tmp .. "'")

local ok, err = testfs.match(tmp, {'a.c','b.c','bogus.c'})
assert(not ok)
assert(err == "file does not exist: " .. tmp .. "/bogus.c")

local ok, err = testfs.match('bogus', {'a.c', 'b.c'},          nil, "directory does not exist: bogus")
assert(not ok)
assert(err == "directory does not exist: bogus")

lfsu.rm_rf(tmp)

print 'passed!'
