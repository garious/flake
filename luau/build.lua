package '../snowflakes'

local system   = require 'system'
local xpfs     = require 'xpfs'
local c        = require 'c'
local lua      = require 'lua'
local list     = require 'list'
local params   = require 'commonParams'

local function testedLuaFile(path, host)
  local sourceFile = path:gsub('(.+)(%.lua)', '%1_q%2')
  if not xpfs.stat(sourceFile) then
    return path
  end

  local requiresHost = list:new {
    'xpexec_q.lua',
    'xpio_q.lua',
  }

  local env = requiresHost:find(sourceFile) and {
    LUA = host,
    PATH = os.getenv 'PATH',
  }

  return lua.run {
    sourceFile = sourceFile,
    validates = path,
    host = host,
    env = env,
  }
end

local function main(ps)
  local xpfsLib = c.library {
    sourceFiles = {'xpfs.c'},
    includeDirs = {lua.tools().path .. "/inc"},
    flavor = ps.flavor,
  }

  local xpioLib = c.library {
    sourceFiles = {'xpio_c.c'},
    includeDirs = {lua.tools().path .. "/inc"},
    flags = {'-Wno-missing-braces'},
    flavor = ps.flavor,
  }

  local luaHost = lua.program {
    luaLibs = {'xpfs', 'xpio_c'},
    libs = {xpfsLib, xpioLib},
  }

  local function toShipPath(k)
    return not k:match '_q%.lua$' and k ~= 'build.lua' and testedLuaFile(k, luaHost) or nil, k
  end

  local luaFiles = system.find {
    pattern = '%.lua'
  }
  local shipFiles = luaFiles:mapWithKeys(toShipPath)

  shipFiles = shipFiles:merge {
    ['xpfs.lib'] = xpfsLib,
    ['xpio_c.lib'] = xpioLib,
  }

  return system.directory {
    path = ps.outdir,
    contents = shipFiles,
  }
end

local function clean(ps)
  return system.removeDirectory(ps.outdir)
end

return {
  main = main,
  clean = clean,
  params = params,
}

