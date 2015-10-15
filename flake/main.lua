function __FILE__() return debug.getinfo(2,'S').source:sub(2,-1) end
function __LINE__() return debug.getinfo(2,'l').currentline end

local path = require 'path'

function __DIR__() return path.takeDirectory(debug.getinfo(2,'S').source:sub(2,-1)) end

-- Disallow reading or writing global variables
setmetatable(_G, {
  __newindex = function (_, n)
    error("attempt to write to undeclared variable "..n, 2)
  end,
  __index = function (_, n)
    error("attempt to read undeclared variable "..n, 2)
  end,
})

-- Save and restore current working directory across context switches
-- Note: This needs to execute before the first require('xpio')
local xpfs = require 'xpfs'
local create, yield = coroutine.create, coroutine.yield
local pack, unpack = table.pack, table.unpack
coroutine.create = function(f)
  local cwd = xpfs.getcwd()
  return create(function(...)
    xpfs.chdir(cwd)
    return f(...)
  end)
end
coroutine.yield = function(...)
  local cwd = xpfs.getcwd()
  local xs = pack(yield(...))
  xpfs.chdir(cwd)
  return unpack(xs)
end

local flakeOpts = require 'flakeOpts'
local flake     = require 'flake'
local xpfs      = require 'xpfs'
local thread    = require 'thread'
local lfsu      = require 'lfsu'
local lua       = require 'lua'
local process   = require 'process'

-- Hack to package list.lua with Flake
-- @require list
-- @require listBuilders
-- @require operatorBuilders
-- @require system
-- @require systemIO
-- @require c
-- @require cIO
-- @require luaIO

-- Make 'package' a function that accepts a directory path and appends it to the lua path
setmetatable(package, {
  __call = function(t, p)
    if xpfs.stat(p) == nil then
      local file = debug.getinfo(2,'S').source:sub(2,-1)
      io.stderr:write('flake: warning: ' .. file .. ': directory does not exist: ' .. p .. '\n')
    end
    if t.path ~= '' then
      t.path = t.path .. ';'
    end
    t.path = t.path .. p .. '/?.lua'
  end,
})

flake.decendThenCall(_G, 'pairs')
flake.decendThenCall(_G, 'ipairs')

local function fatal(msg)
  io.stderr:write('flake: ' .. msg .. '\n')
  os.exit(1)
end

local function info(msg)
  io.stdout:write('flake: ' .. msg .. '\n')
end

local function optsError(msg)
  fatal(msg .. '\n' .. flakeOpts.usage)
end

-- Collect args until the second set of options.
--    When running as a Lua script, that second set of args is intended
--    for the target script.
-- Given:  "-a -b c d -e -f", return "-a -b c d"
local function collectArgs(xs)
  local args = {}
  local gotit = false
  for _,v in ipairs(xs) do
    if v:sub(1,1) ~= '-' then
      gotit = true
    end
    if gotit and v:sub(1,1) == '-' then
      break
    end
    table.insert(args, v)
  end
  return args
end

local function main()
  local args = collectArgs(arg)
  local options, targetArgs = flakeOpts.parseArgs(args, optsError)
  table.remove(arg, 1)

  local luaExe = arg[-1] or arg[0]
  lua.configure {
    luaExe = xpfs.stat(luaExe) and lfsu.abspath(luaExe) or process.findExecutable(luaExe),
  }

  if options.version then
    print 'flake 0.9.0'
    os.exit(0)
  end

  flake.configure{
    cache = not options.penniless,
    quiet = options.quiet,
    silent = options.silent,
  }

  package.path = os.getenv 'LUA_PATH' or './?.lua'

  if type(options.package) == 'table' then
    for _,v in ipairs(options.package) do
      package(v)
    end
  end

  local oldDir
  if options.directory ~= '.' then
    oldDir = xpfs.getcwd()
    if not options.silent then
      info("Entering directory '" .. lfsu.abspath(options.directory) .. "'")
    end
    local ok, err = xpfs.chdir(options.directory)
    if not ok then
      fatal(err)
    end
  end

  -- "flake clean" -> "flake build.lua clean"
  if options.file == 'clean' then
    -- Shift targetArgs down one
    for i=#targetArgs,1,-1 do
      targetArgs[i+1] = targetArgs[i]
    end

    -- Make 'clean' the first target arg
    targetArgs[1] = options.file

    -- Make 'build.lua' the file
    options.file = 'build.lua'
  end

  local targetMap

  if options.e or options[''] then
    local input = options.e or io.read('*a')
    local targetMapFunc, err = load(input)
    if targetMapFunc == nil then
      fatal(err)
    end
    local ok, err = xpcall(targetMapFunc, debug.traceback)
    if not ok then
      fatal(err)
    else
      targetMap = err
    end
  elseif xpfs.stat(options.file) then
    local targetMapFunc, err = loadfile(options.file)
    if targetMapFunc == nil then
      fatal(err)
    end
    local ok, err = xpcall(targetMapFunc, debug.traceback)
    if not ok then
      fatal(err)
    else
      targetMap = err
    end
  else
    local ok, err = pcall(require,options.file)
    if ok then
      targetMap = err
    else
      fatal('Cannot find file or Lua module \'' .. options.file .. '\'.\n')
    end
  end

  -- If target map is a builder, it is the 'main' target
  local target = 'main'
  if flake.isBuilder(targetMap) then
    local builder = targetMap
    targetMap = {main = function() return builder end}
  elseif type(targetMap) == 'function' then
    targetMap = {main = targetMap}
  elseif type(targetMap) == 'table' then
    target = targetArgs[1] or 'main'
    for i,v in ipairs(targetArgs) do
      if i > 1 then
        targetArgs[i-1] = targetArgs[i]
        targetArgs[i] = nil
      end
    end
  else
    os.exit(0)
  end

  local f = targetMap[target]

  if f then
    assert(type(f) == 'function')
    if type(targetMap.params) == 'table' then
      targetArgs = flake.validate('.', targetMap.params, targetArgs)
    end

    local x = f(targetArgs)

    local didWork = false
    local function compute(o, ...)
      if not o.isPure then
        didWork = true
      end
      return flake.computeValue(o, ...)
    end

    local ok, err, val = xpcall(flake.lower, debug.traceback, x, compute)
    if not ok or err ~= nil then
      fatal('*** ' .. err)
    elseif not didWork then
      io.stderr:write('flake: Nothing to be done for \'' .. target .. '\'.\n')
    end
  elseif target ~= 'clean' then
    fatal('Target not found \'' .. target .. '\'.')
  end
  if target == 'clean' then
    lfsu.rm_rf(flake.getBuildDirectory())
    flake.clearCache()
  end

  if oldDir then
    if not options.silent then
      info("Leaving directory '" .. xpfs.getcwd() .. "'")
    end
    xpfs.chdir(oldDir)
  end
end

thread.dispatch(main)

