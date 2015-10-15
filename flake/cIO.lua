local systemIO = require 'systemIO'
local process  = require 'process'
local path     = require 'path'
local lfsu     = require 'lfsu'
local list     = require 'list'

local flavors = {
  release = {'-Wall', '-Werror', '-O2'},
  debug   = {'-Wall', '-g', '-D_DEBUG'},
}

local osName
local function init()
  local err
  err, osName = process.readProcess 'uname'
  assert(not err, err)
end

local config = {
   cc  = os.getenv('CC')  or 'clang',
   cxx = os.getenv('CXX') or 'clang++',
   ar  = os.getenv('AR')  or 'ar',
}

local function isCxx(p)
  return path.takeExtension(p) ~= '.c'
end

local function chooseCompiler(xs)
  local cxxFile = list.find(xs, isCxx)
  return config[cxxFile and 'cxx' or 'cc']
end

local function program(cfg, ps)
  if osName == nil then
    init()
  end

  local sourceFiles = ps.sourceFiles or {ps.sourceFile or ps[1]}
  local name = ps.name or cfg.outPath or (sourceFiles[1] and cfg.buildDir .. '/' .. path.takeBaseName(sourceFiles[1]))

  local cc = ps.cc or chooseCompiler(sourceFiles)

  -- TODO: check isatty() before adding -fcolor-diagnostics
  local args = {cc, '-o', name}

  if type(ps.includeDirs) == 'table' then
    for i,v in ipairs(ps.includeDirs) do
      table.insert(args, '-I'..v)
    end
  end

  if type(sourceFiles) == 'table' then
    for i,v in ipairs(sourceFiles) do
      table.insert(args, v)
    end
  end

  if type(ps.libs) == 'table' then
    for i,v in ipairs(ps.libs) do
      table.insert(args, v)
    end
  end

  for _,v in ipairs(flavors[ps.flavor] or {}) do
    table.insert(args, v)
  end
  for _,v in ipairs(ps.flags or {}) do
    table.insert(args, v)
  end


  local env = {}
  if osName == 'Darwin' or (osName == 'Linux' and cc:match('gcc$')) then
    -- On Darwin, path to 'ld'
    -- On Linux and CC=gcc, path to tool that finds 'cc1'
    env.PATH = '/usr/bin'
  end

  local outdir = path.takeDirectory(name)
  lfsu.mkdir_p(outdir)
  return systemIO.execute(cfg, {args=args, env=env, thenReturn=name})
end

local function object(cfg, ps)
  if osName == nil then
    init()
  end

  local sourceFile = ps.sourceFile
  local name = ps.name or cfg.outPath or (sourceFile and cfg.buildDir .. '/' .. path.takeBaseName(sourceFile) .. '.o')
  local cc = ps.cc or chooseCompiler{sourceFile}
  local args = {cc, '-o', name, '-c'}

  if type(ps.includeDirs) == 'table' and #ps.includeDirs > 0 then
    for i,v in ipairs(ps.includeDirs) do
      table.insert(args, '-I'..v)
    end
  end
  for _,v in ipairs(flavors[ps.flavor] or {}) do
    table.insert(args, v)
  end
  for _,v in ipairs(ps.flags or {}) do
    table.insert(args, v)
  end
  table.insert(args, ps.sourceFile)

  local outdir = path.takeDirectory(name)

  local env = {}
  if osName == 'Linux' and cc:match('gcc$') then
    -- On Linux and CC=gcc, path to tool that finds 'cc1'
    env.PATH = '/usr/bin'
  end

  lfsu.mkdir_p(outdir)
  return systemIO.execute(cfg, {args=args, env=env, thenReturn=name})
end

local function library(cfg, ps)
  local objectFiles = ps.objectFiles or {}
  local name = ps.name or cfg.outPath or (objectFiles[1] and (path.dropExtension(objectFiles[1])) .. '.lib')
  if name == nil then
    error 'No input files'
  end
  local args = {ps.ar, 'rcs', name}

  if type(objectFiles) == 'table' and #objectFiles > 0 then
    for i,v in ipairs(objectFiles) do
      table.insert(args, v)
    end
  end

  local outdir = path.takeDirectory(name)
  lfsu.mkdir_p(outdir)
  return systemIO.execute(cfg, {args=args, thenReturn=name})
end

return {
  config = config,
  program = program,
  library = library,
  object = object,
}

