--
-- Read/Write test
--

local flake    = require 'flake'
local thread   = require 'thread'
local lfsu     = require 'lfsu'
local qt       = require 'qtest'

local function sparkWithFile(path)
  local info = {getInputFiles = function(cfg, src) return {src} end}
  local f = flake.lift(function() end, 'foo', info)
  local o = f(path)
  local err, v = flake.spark(o._priv, function() end)
  if err == nil and type(v) == 'table' and getmetatable(v) == thread.Task then
    err, v = thread.join(v)
  end
  return err
end

local function testSpark()
  local out = os.getenv 'OUTDIR'
  local p = out .. '/foo.txt'
  lfsu.mkdir_p(out)
  lfsu.write(p, 'FOO\n')

  qt.eq(sparkWithFile(p), nil)

  -- Reentrant
  qt.eq(sparkWithFile(p), nil)

  -- File deleted.
  lfsu.rm_rf(p)
  qt.eq(sparkWithFile(p), "File not found '" .. p .. "'.")
end

local function testSparkWithBogusFile()
  qt.eq(sparkWithFile('bogus'), "File not found 'bogus'.")
end

local function testLowering()
  -- Initialize
  local out = flake.getBuildDirectory()
  lfsu.mkdir_p(out)
  lfsu.write(out .. '/foo.txt', 'FOO\n')

  -- Override Flake functions to gather stats
  local results = {}
  local recomputations = 0
  local function compute(...)
    recomputations = recomputations + 1
    return flake.computeValue(...)
  end
  --

  local function readWriteRead(sys)
    local p = sys.createDirectory(out)
    local s = sys.readFile(p .. '/foo.txt')      -- 'p' is a file handle so '..' creates a builder
    local f = sys.writeFile(p .. '/bar.txt', s)
    return sys.readFile(f)
  end

  local f1 = readWriteRead(flake.requireWrapped 'systemIO')
  local f2 = readWriteRead(flake.requireBuilders 'systemIO')

  assert(f1 == 'FOO\n')

  local err, val = flake.lower(f2, compute)
  assert(err == nil, err)
  assert(f1 == val)

  -- Nodes: createDirectory, readFile, '..', writeFile, readFile
  assert(recomputations == 6, recomputations)

  -- Again!
  recomputations = 0
  local err, val = flake.lower(f2, compute)
  assert(err == nil, err)
  assert(f1 == val)
  assert(recomputations == 0, recomputations) -- No need to recompute 'readFile' calls

  -- Again!
  flake.configure{cache = false}
  local f3 = readWriteRead(flake.requireBuilders 'systemIO')
  local err, val = flake.lower(f3, compute)
  assert(err == nil, err)
  assert(f1 == val)
end

local function runWithDB(dbDir, f)
  -- Initialize
  flake.configure{buildDir = dbDir, silent = true}
  lfsu.rm_rf(dbDir)
  local out = flake.getBuildDirectory()
  lfsu.mkdir_p(out)

  -- Run
  local ok, err = xpcall(f, debug.traceback)

  -- Cleanup
  lfsu.rm_rf(dbDir)
  if not ok then
    error(err, 0)
  end
end

local function main()
  local dbDir = os.getenv 'OUTDIR' .. '/flake'
  runWithDB(dbDir, testSpark)
  runWithDB(dbDir, testSparkWithBogusFile)
  runWithDB(dbDir, testLowering)
end

thread.dispatch(main)

print('passed!')

