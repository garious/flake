local thisDir = __DIR__()

local systemIO = require 'systemIO'
local cIO      = require 'cIO'
local path     = require 'path'
local list     = require 'list'
local lfsu     = require 'lfsu'
local process  = require 'process'

local function mkLuaPath(dirs)
  local luaPath = '?.lua'
  if type(dirs) == 'table' then
    local luaPaths = {}
    for i,v in ipairs(dirs) do
      table.insert(luaPaths, v .. '/?.lua')
    end
    luaPath = table.concat(luaPaths, ';')
  end
  return luaPath
end

local function insertIncParams(t, xs)
  for _,x in ipairs(xs) do
    table.insert(t, '-I')
    table.insert(t, x)
  end
end

local function insertLibParams(t, xs)
  for _,x in ipairs(xs) do
    table.insert(t, '--open=' .. x)
  end
end

local function parseDeps(s, ignore)
  local t = list:new()
  for v in s:gmatch('[^:]+:%s*([^\r\n]+)') do
    -- split by spaces
    for v in v:gmatch('([^%s\r\n]+)') do
      if v ~= ignore then
        table.insert(t, v)
      end
    end
  end
  return t
end

local function dependencies(cfg, ps)
  assert(ps.lua, 'luaIO.dependencies: path to lua binary not provided')
  local sourceFile = ps.sourceFile or ps[1]

  local luaDeps = require 'luaDeps'
  if sourceFile == nil then
    sourceFile = cfg.buildDir .. '/interpreter.lua'
    lfsu.mkdir_p(cfg.buildDir)
    lfsu.write(sourceFile, luaDeps.interpreter)
  end

  lfsu.mkdir_p(cfg.buildDir)
  lfsu.write(cfg.buildDir .. '/cfromlua.lua', luaDeps.cfromlua)

  local args = {
    ps.lua,
    cfg.buildDir .. '/cfromlua.lua',
    '-MT', '-',
    '-MF', '-',
  }

  insertIncParams(args, ps.luaPathDirs or {})
  table.insert(args, sourceFile)

  local err, ds, stderr = process.readProcess(args)
  if err then
    return stderr or err
  end
  return nil, parseDeps(ds, sourceFile)
end

local function luaCFile(cfg, ps)
  assert(ps.lua, 'luaIO.luaCFile: path to lua binary not provided')
  assert(type(ps.name) == 'string', type(ps.name))
  local outdir = path.takeDirectory(ps.name)
  lfsu.mkdir_p(outdir)

  local luaDeps = require 'luaDeps'
  lfsu.mkdir_p(cfg.buildDir)
  lfsu.write(cfg.buildDir .. '/cfromlua.lua', luaDeps.cfromlua)

  local args = {
    ps.lua,
    cfg.buildDir .. '/cfromlua.lua',
    '-o', ps.name,
    '--minify',
  }
  insertIncParams(args, ps.luaPathDirs or {})
  insertLibParams(args, ps.luaLibs or {})
  for _,v in ipairs(ps.sourceFiles) do
    table.insert(args, v)
  end
  return systemIO.execute(cfg, {args=args, thenReturn=ps.name})
end

local function program(cfg, ps)
  assert(ps.lua, 'luaIO.program: path to lua binary not provided')
  local sourceFiles = ps.sourceFiles or {ps.sourceFile or ps[1]}

  local luaDeps = require 'luaDeps'
  if sourceFiles[1] == nil then
    sourceFiles[1] = cfg.buildDir .. '/interpreter.lua'
    lfsu.mkdir_p(cfg.buildDir)
    lfsu.write(sourceFiles[1], luaDeps.interpreter)
  end

  local name = ps.name or cfg.outPath or (sourceFiles[1] and cfg.buildDir .. '/' .. path.takeBaseName(sourceFiles[1]))
  local cFileName = cfg.buildDir .. '/' .. path.takeFileName(name) .. '.c'
  local err, cFile = luaCFile(cfg, {
    name = cFileName,
    sourceFiles = sourceFiles,
    luaLibs = ps.luaLibs,
    luaPathDirs = ps.luaPathDirs,
    lua = ps.lua,
  })
  if err then
    return err
  end

  local flags = {'-lm', '-ldl'}
  flags = ps.flags and list.append(flags, ps.flags) or flags

  return cIO.program(cfg, {
    name = name,
    sourceFiles = {cFile},
    includeDirs = ps.includeDirs,
    libs = ps.libs,
    flags = flags,
    flavor = ps.flavor,
    cc = ps.cc,
  })
end

local function run(cfg, ps)
  lfsu.mkdir_p(cfg.buildDir)
  local luaPath = mkLuaPath(ps.luaPathDirs)
  local sourceFile = ps.sourceFile or ps[1]
  local env = {
    LUA_PATH = luaPath,
    OUTDIR = cfg.buildDir,
  }
  for k,v in pairs(ps.env or {}) do
    env[k] = v
  end
  local args = {ps.host, sourceFile}
  for _,v in ipairs(ps.args or {}) do
    table.insert(args, v)
  end
  return systemIO.execute(cfg, {args=args, env=env, thenReturn=ps.validates})
end

local function writeDirectory(p, x)
  if type(x) == 'string' then
    assert(lfsu.write(p, x))
    return p
  else
    lfsu.mkdir_p(p)
    local t = {}
    for k,v in pairs(x) do
      t[k] = writeDirectory(p..'/'..k, v)
    end
    return t
  end
end

local function tools(cfg)
  local luaDeps = require 'luaDeps'
  return nil, {
    path = cfg.buildDir,
    contents = writeDirectory(cfg.buildDir, {
      src = {
        ['cfromlua.lua']    = luaDeps.cfromlua,
        ['interpreter.lua'] = luaDeps.interpreter,
      },
      lib = {
        ['liblua.lib'] = luaDeps.liblua,
      },
      inc = {
        ['lauxlib.h'] = luaDeps.inc['lauxlib.h'],
        ['lua.h']     = luaDeps.inc['lua.h'],
        ['luaconf.h'] = luaDeps.inc['luaconf.h'],
        ['lualib.h']  = luaDeps.inc['lualib.h'],
      },
    }),
  }
end

return {
  dependencies = dependencies,
  dependencies__info = {
    outputMetatable = list,
  },
  program = program,
  run = run,
  tools = tools,
}
