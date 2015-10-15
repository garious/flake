local xpexec = require 'xpexec'
local xpfs   = require 'xpfs'
local thread = require 'thread'
local xpio   = require 'xpio'
local lfsu   = require 'lfsu'
local list   = require 'list'

local concat = table.concat

-- Read all data from `s`, appending to table `output`
--
local function readFrom(s, output)
   repeat
      local data, err = s:read(4096)
      if data then
         table.insert(output, data)
      else
         s:close()
         return
      end
   until false
end

local function execute(cfg, ps)
  local r0, w0 = xpio.pipe()   -- stdin
  local r1, w1 = xpio.pipe()   -- stdout
  local r2, w2 = xpio.pipe()   -- stderr

  w0:close() -- Nothing to write on stdin

  local stdoutLines = {}
  local stderrLines = {}

  if type(ps) == 'table' and ps[1] then
    ps = {args = ps}
  end

  assert(type(ps.args) == 'table', tostring(ps.args))

  local proc = assert(xpio.spawn(ps.args, ps.env or {}, {[0]=r0, [1]=w1, [2]=w2}))
  local t1 = thread.new(readFrom, r1, stdoutLines)
  local t2 = thread.new(readFrom, r2, stderrLines)

  local reason, code = proc:wait()

  local stdout = cfg and cfg.io and cfg.io[1] or io.stdout
  local stderr = cfg and cfg.io and cfg.io[2] or io.stderr

  -- Wait until after command returns before printing that we
  -- executed it.  If other commands are running in parallel,
  -- this will ensure the output is right after the command.
  if not cfg.quiet then
    local envStr = ''
    if type(ps.env) == 'table' then
      local function mkEnvArg(k)
        return k .. '=' .. xpexec.quoteArg(ps.env[k])
      end
      local ks = list.keys(ps.env)
      table.sort(ks)
      if #ks > 0 then
        envStr = concat(list.map(ks, mkEnvArg), ' ') .. ' '
      end
    end
    stdout:write('$ ' .. envStr .. concat(ps.args, ' ') .. '\n')
  end

  thread.join(t1)
  thread.join(t2)
  for _,v in ipairs(stdoutLines) do stdout:write(v) end
  for _,v in ipairs(stderrLines) do stderr:write(v) end

  if code == 0 then
    code = nil
  end

  return code, ps.thenReturn
end

local function createDirectory(cfg, p)
  assert(type(p) == 'string', type(p))
  lfsu.mkdir_p(p)
  return nil, p
end

local function removeDirectory(cfg, p)
  assert(type(p) == 'string', type(p))
  lfsu.rm_rf(p)
  return nil, p
end

local function writeFile(cfg, p, s)
  local f = assert(io.open(p, 'wb'))
  f:write(s)
  f:close()
  return nil, p
end

local function readFile(cfg, p)
  local f = assert(io.open(p, 'rb'))
  local s = f:read('*a')
  f:close()
  return nil, s
end

local function copyFile(cfg, src, tgt)
  local r = assert(io.open(src, 'rb'))
  local w = assert(io.open(tgt, 'wb'))
  local sz = 2^13 -- 8KB
  while true do
    local s = r:read(sz)
    if not s then
      break
    end
    w:write(s)
  end
  r:close()
  w:close()

  --TODO: copy file attributes

  return nil, tgt
end

local function _directory(cfg, tgt, src)
  if type(src) == 'string' then
    if lfsu.abspath(src) == lfsu.abspath(tgt) then
      return tgt
    else
      local err, tgt = copyFile(cfg, src, tgt)
      if err ~= nil then
        error(err)
      end
      return tgt
    end
  elseif type(src) == 'table' then
    createDirectory(cfg, tgt)
    local t = {}
    for nm, spec in pairs(src) do
      t[nm] = _directory(cfg, tgt .. '/' .. nm, spec)
    end
    return t
  else
    error('expected table or string, but got: ' .. type(src))
  end
end

local function directory(cfg, spec)
  if type(spec.contents) ~= 'table' then
    error('expected table, but got: ' .. type(spec.contents))
  end
  local p = spec.path or cfg.buildDir
  return nil, {
    path = p,
    contents = _directory(cfg, p, spec.contents),
  }
end

-- Test if a file xists
local function fileExists(cfg, path)
  local attrs, err = xpfs.stat(path)
  return nil, attrs ~= nil and attrs.kind == 'f'
end

-- Test if a directory exists
local function directoryExists(cfg, path)
  local attrs, err = xpfs.stat(path)
  return nil, attrs ~= nil and attrs.kind == 'd'
end

local function find(cfg, ps)
  local p = ps.directory or '.'
  local t = list:new()
  for _, s in ipairs(xpfs.dir(p)) do
    if s ~= '.' and s ~= '..' and s:match(ps.pattern) then
      table.insert(t, p == '.' and s or p..'/'..s)
    end
  end
  table.sort(t)
  return nil, t
end

return {
  copyFile              = copyFile,
  copyFile__info = {
    getInputFiles = function(cfg,src,tgt) return {src} end,
  },
  createDirectory       = createDirectory,
  execute               = execute,
  fileExists            = fileExists,
  directory             = directory,
  directoryExists       = directoryExists,
  find                  = find,
  find__info = {
    outputMetatable  = list,
    getInputFiles = function(cfg,p,s) return nil end, -- Always run
  },
  readFile              = readFile,
  removeDirectory       = removeDirectory,
  removeDirectory__info = {
    getInputFiles = function(cfg,p,s) return nil end, -- Always run
  },
  writeFile             = writeFile,
  writeFile__info       = {
    getInputFiles = function(cfg,p,s) return {} end,
  },
}

