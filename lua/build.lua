package '../snowflakes'

local flake    = require 'flake'
local process  = require 'process'
local system   = require 'system'
local c        = require 'c'
local params   = require 'commonParams'
local list     = require 'list'
local path     = require 'path'

local err, osName = process.readProcess 'uname'
assert(not err, err)

local flagsPerOs = {
  WinNT  = {'-D_CRT_SECURE_NO_DEPRECATE'},
  Linux  = {'-DLUA_USE_POSIX', '-D_GNU_SOURCE', '-DLUA_USE_DLOPEN'},
  Darwin = {'-DLUA_USE_POSIX', '-D_GNU_SOURCE', '-DLUA_USE_DLOPEN'},
}

local ldFlagsPerOs = {
  Linux = {'-Wl,--export-dynamic'}
}

local luaSrcDir = 'lua-5.3.1/src'

local exeFiles = list:new {'lua.c', 'luac.c', 'print.c'}

local function notMain(p)
  local nm = path.takeFileName(p)
  return exeFiles:find(nm) == nil
end

local sourceFiles = system.find {
  directory = luaSrcDir,
  pattern = '%.c$',
}
sourceFiles = sourceFiles:filter(notMain)

local function main(ps)
  local liblua = c.library {
    sourceFiles = sourceFiles,
    flavor = ps.flavor,
    flags = flagsPerOs[osName],
  }

  local ldFlags = {'-lm', '-ldl'}
  local osFlags = flagsPerOs[osName]
  ldFlags = osFlags and list.append(ldFlags, osFlags) or ldFlags

  local ldOsFlags = ldFlagsPerOs[osName]
  ldFlags = ldOsFlags and list.append(ldFlags, ldOsFlags) or ldFlags

  return system.directory {
    path = ps.outdir,
    contents = {
      ['lib'] = {
        ['liblua.lib'] = liblua,
      },
      ['bin'] = {
        ['lua'] = c.program {
          sourceFiles = {luaSrcDir .. '/lua.c'},
          libs = {liblua},
          flavor = ps.flavor,
          flags = ldFlags,
        },
      },
      ['src'] = {
        ['lauxlib.h'] = luaSrcDir .. '/lauxlib.h',
        ['lua.h']     = luaSrcDir .. '/lua.h',
        ['luaconf.h'] = luaSrcDir .. '/luaconf.h',
        ['lualib.h']  = luaSrcDir .. '/lualib.h',
      },
    },
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

