local systemIO = require 'systemIO'
local flake    = require 'flake'
local list     = require 'list'
local lfsu     = require 'lfsu'

lfsu.mkdir_p('tmp')
lfsu.write('tmp/a.c', 'foo\n')
lfsu.write('tmp/b.c', 'foobar\n')

--
-- find()
--
-- find() must be deterministic.  Verify it returns a sorted list.
local err, files = systemIO.find({}, {directory='tmp', pattern='%.c$'})
assert(err == nil)
assert(list.eq(files, {'tmp/a.c', 'tmp/b.c'}), list.tostring(files))

--
-- defaultGetInputFiles
--
local function assertInputs(contents, exp)
  local act = flake.defaultGetInputFiles{contents = contents}
  act = list.sort(act)
  exp = list.sort(exp)
  local ok = list.eq(act, exp)
  if not list.eq(act, exp) then
    assert(false, '\nexpected: ' .. list.tostring(exp) .. '\n but got: ' .. list.tostring(act))
  end
end
assertInputs({a={b='tmp/b.c'}}          , {'tmp/b.c'})             -- Nested directory
assertInputs({a='tmp/a.c', b='tmp/b.c'} , {'tmp/a.c', 'tmp/b.c'})  -- Multiple files

lfsu.rm_rf('tmp')

print 'passed!'
