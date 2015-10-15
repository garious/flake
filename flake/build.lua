package '../snowflakes'

local flake        = require 'flake'
local system       = require 'system'
local ops          = require 'operatorBuilders'
local params       = require 'commonParams'

local function bootstrapLua(ps)
  -- Bootstrap Lua builders
  local luaDir = flake.importBuilt('../lua').main(ps)
  local luaCnts = luaDir.contents

  local lfsu         = require 'lfsu'
  local serialize    = require 'serialize'

  local deps = {
    cfromlua    = lfsu.read '../cfromlua/cfromlua.lua',
    interpreter = lfsu.read '../cfromlua/interpreter.lua',
    inc = {
      ['lauxlib.h'] = lfsu.read(luaCnts.src['lauxlib.h']),
      ['lua.h']     = lfsu.read(luaCnts.src['lua.h']),
      ['luaconf.h'] = lfsu.read(luaCnts.src['luaconf.h']),
      ['lualib.h']  = lfsu.read(luaCnts.src['lualib.h']),
    },
    liblua = lfsu.read(luaCnts.lib['liblua.lib']),
  }
  lfsu.write('luaDeps.lua', 'return ' .. serialize.serialize(deps, nil, 's'))

  return require 'lua'
end

local function main(ps)
  local lua = bootstrapLua(ps)

  local sha1Dir      = flake.importBuild('../sha1').main(ps)
  local luauDir      = flake.importBuild('../luau').main(ps)

  local luaPathDirs = {'.', luauDir.path}

  local function integrationTests(shipDir)
    local flakeExe = shipDir.contents['flake']

    local commandLineTests = lua.run {
      sourceFile = 'flakeExe_q.lua',
      host = flakeExe,
      args = {flakeExe},
      luaPathDirs = luaPathDirs,
      validates = flakeExe,
    }

    local multiProjectExample = system.execute {
      args = {flakeExe, '-C', 'test', '--silent'},
      thenReturn = flakeExe,
    }
    return ops.first(commandLineTests, multiProjectExample)
  end

  return integrationTests(
    system.directory {
      path = ps.outdir,
      contents = {
        ['flake'] = lua.program {
          sourceFile = 'main.lua',
          flavor = ps.flavor,
          luaLibs = {'sha1', 'xpfs', 'xpio_c'},
          libs = {
            sha1Dir.contents['libsha1.lib'],
            luauDir.contents['xpfs.lib'],
            luauDir.contents['xpio_c.lib'],
          },
          luaPathDirs = luaPathDirs,
          env = {PATH = os.getenv 'PATH'},
        },
      },
    }
  )
end

local function clean(ps)
  return system.removeDirectory(ps.outdir)
end

return {
  main = main,
  clean = clean,
  params = params,
}
