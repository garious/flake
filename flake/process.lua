local thread = require 'thread'
local xpio   = require 'xpio'
local xpfs   = require 'xpfs'

local concat = table.concat

-- Read all data from `f`, appending to table `t`
--
local function readFrom(f, t)
  repeat
    local s, err = f:read(4096)
    if s then
      table.insert(t, s)
    else
      f:close()
      return
    end
  until false
end

local function findExecutable(nm)
  local s = os.getenv 'PATH'
  if s == nil then
    return nil
  end
  for p in s:gmatch('[^:]+') do
    p = p .. '/' .. nm
    local x = xpfs.stat(p)
    if x and x.kind == 'f' then
      return p
    end
  end
  return nil
end

local function readProcess(args, env, stdinStr)
  if type(args) == 'string' then
    args = {args}
  end
  assert(type(args) == 'table', type(args))
  assert(type(args[1]) == 'string', type(args[1]))

  local r0, w0 = xpio.pipe()   -- stdin
  local r1, w1 = xpio.pipe()   -- stdout
  local r2, w2 = xpio.pipe()   -- stderr

  local stdoutChunks = {}
  local stderrChunks = {}

  local proc, err = xpio.spawn(args, env or {}, {[0]=r0, [1]=w1, [2]=w2})
  if proc == nil then
    return err
  end

  if type(stdinStr) == 'string' then
    w0:write(stdinStr)
  end
  w0:close()

  local th1 = thread.new(readFrom, r1, stdoutChunks)
  local th2 = thread.new(readFrom, r2, stderrChunks)

  local reason, code = proc:wait()
  thread.join(th1)
  thread.join(th2)

  -- Trim trailing whitespace
  local stdout = concat(stdoutChunks):gsub('%s+$', '')
  local stderr = concat(stderrChunks):gsub('%s+$', '')

  if code == 0 then
    code = nil
  end

  return code, stdout, stderr, reason
end

return {
  findExecutable = findExecutable,
  readProcess = readProcess,
}

