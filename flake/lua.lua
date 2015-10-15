-- Flake builders for Lua programs

local thisDir = __DIR__()

local flake        = require 'flake'
local list         = require 'list'
local xpfs         = require 'xpfs'
local c            = require 'c'
local lfsu         = require 'lfsu'
local lua          = flake.requireBuilders 'luaIO'

local config = {
  luaExe = nil,
  luaLib = nil,
  luaInc = nil,
}

-- Note: We can't call init() at the top-level because
--       it triggers a coroutine.yield() which can't
--       be done across C boundaries as of Lua 5.2.2.
local function init()
  local err, luaDir = flake.lower(lua.tools())
  assert(not err, err)

  -- We use absolute paths here, because flake may
  -- change directories on us.
  config.luaLib = lfsu.abspath(luaDir.contents.lib['liblua.lib'])
  config.luaInc = lfsu.abspath(luaDir.path .. '/inc')
end

-- Add a default lua host to generate dependencies with
local dependencies = lua.dependencies
lua.dependencies = function(ps)
  if not config.luaExe then
    init()
  end
  if ps.lua == nil then
    ps = list.clone(ps)
    ps.lua = config.luaExe
  end
  return dependencies(ps)
end

-- Extend the program builder to scan for dependencies
local program = lua.program
lua.program = function(ps)
  if not config.luaInc then
    init()
  end
  ps = list.clone(ps)
  ps.lua = config.luaExe
  ps.includeDirs = {config.luaInc}
  ps.libs = list.clone(ps.libs or {}) -- Since we modify ps.libs, we need to clone it.
  table.insert(ps.libs, config.luaLib)

  -- Set C compiler
  ps.cc = ps.cc or c.getCC()

  local deps = dependencies {
    sourceFile  = ps.sourceFile or ps[1],
    luaPathDirs = ps.luaPathDirs,
    lua         = config.luaExe,
  }

  local luaHost = program {
    luaLibs = ps.luaLibs,
    libs = ps.libs,
    includeDirs = ps.includeDirs,
    lua = config.luaExe,
    cc = ps.cc,
  }

  local function testedLuaFile(path)
    local sourceFile = path:gsub('(.+)(%.lua)', '%1_q%2')
    if xpfs.stat(sourceFile) == nil then
      return path
    end

    return lua.run {
      sourceFile = sourceFile,
      validates = path,
      host = luaHost,
      luaPathDirs = ps.luaPathDirs,
      env = ps.env,
    }
  end

  ps.dependencies = deps:map(testedLuaFile)
  return program(ps)
end

-- Extend the 'run' builder to scan for dependencies
-- and to use the lua executable by default.
local run = lua.run
lua.run = function(ps)
  assert(type(ps) == 'table', type(ps))
  if not config.luaExe then
    init()
  end
  ps = list.clone(ps)

  -- Set C compiler
  ps.cc = ps.cc or c.getCC()

  ps.dependencies = lua.dependencies {
    sourceFile  = ps.sourceFile or ps[1],
    luaPathDirs = ps.luaPathDirs,
    lua         = config.luaExe,
  }

  if ps.host == nil then
    ps.host = config.luaExe
  end
  return run(ps)
end

lua.configure = function(ps)
  for k,v in pairs(ps) do
    config[k] = v
  end
end

return lua

