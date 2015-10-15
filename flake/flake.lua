local serialize = require 'serialize'
local operator  = require 'operator'
local sha1      = require 'sha1'
local xpfs      = require 'xpfs'
local xpio      = require 'xpio'
local list      = require 'list'
local lfsu      = require 'lfsu'
local thread     = require 'thread'

local config = {
  cache = true,
  quiet = false,
  silent = false,
  databaseName = 'cache.lua',
  buildDir = '.flake',
}

local function serializeSorted(x)
  return serialize.serialize(x, nil, 's')
end

local function getDatabasePath()
  return config.buildDir .. '/' .. config.databaseName
end

local function save(db)
  lfsu.mkdir_p(config.buildDir)
  local f = assert(io.open(getDatabasePath(), 'w'))
  f:write('return ' .. serializeSorted(db))
  f:close()
end

local dbOfDatabases = {}

local function initDatabase()
  local p = getDatabasePath()
  local cwd = xpfs.getcwd()
  if dbOfDatabases[cwd] == nil then
    local f = io.open(p)
    if f then
      f:close()
      dbOfDatabases[cwd] = loadfile(p)()
    else
      dbOfDatabases[cwd] = {results={}}
    end
  end
  return dbOfDatabases[cwd]
end

local function chdir(p)
  xpfs.chdir(p)
  return initDatabase()
end

local function getDatabase()
  return dbOfDatabases[xpfs.getcwd()]
end

local builderMeta = {}
local function isBuilder(v)
  return type(v) == 'table' and getmetatable(v) == builderMeta
end

-- Return an array of all builders for the given value
local function getBuilders(v, t, h)
  t = t or {} -- array for results
  h = h or {} -- hash for detecting loops
  if v ~= nil and h[v] == nil then
    h[v] = true
    if isBuilder(v) then
      table.insert(t, v)
      getBuilders(v._priv.args, t, h)
    elseif type(v) == 'table' then
      for k,val in pairs(v) do
        getBuilders(val, t, h)
      end
    end
  end
  return t
end

local function isTask(t)
  return type(t) == 'table' and getmetatable(t) == thread.Task
end

local threadBuilderMap = {}

-- forward-declare the 'spark' function.
local spark

local function startLowering(v, compute)
  -- if an argument is a builder, spark a thread that returns its value
  local err
  if isBuilder(v) then
    local th
    if v._priv.activeThunk then
      th = v._priv.activeThunk
    else
      err, th = spark(v._priv, compute)
    end
    if err == nil then
      if isTask(th) then
        v._priv.activeThunk = th
        threadBuilderMap[th] = v
      end
      v = th
    end
  elseif type(v) == 'table' and not isBuilder(v) then
    local t = setmetatable({}, getmetatable(v))
    for k,val in pairs(v) do
      err, t[k] = startLowering(val, compute)
      if err ~= nil then
        break
      end
    end
    v = t
  end
  return err, v
end

local function finishLowering(v)
  if isTask(v) then
    local th = v
    local err
    err, v = thread.join(th)
    if err then
      return err
    end

    if threadBuilderMap[th] then
      threadBuilderMap[th]._priv.activeThunk = nil
      threadBuilderMap[th] = nil
    end
  elseif type(v) == 'table' and not isBuilder(v) then
    local t = setmetatable({}, getmetatable(v))
    for k,val in pairs(v) do
      local err
      err, t[k] = finishLowering(val)
      if err ~= nil then
        return err
      end
    end
    v = t
  end
  return nil, v
end

-- lower one level
local function decend(v, compute)
  -- Spark a thread for each builder
  local err, v = startLowering(v, compute)
  if err ~= nil then
    return err, v
  end

  -- Wait for all threads to complete
  return finishLowering(v)
end

local function lower(v, compute)
  local err, v = decend(v, compute)
  if err ~= nil then
    return err, v
  end

  -- If any builder returned builders, lower them too.
  if #getBuilders(v) > 0 then
    return lower(v, compute)
  else
    return nil, v
  end
end

-- Buffered write all data from first file to second file
-- The first file is then closed.  The second is not.
local function pipeAllToFile(s, output)
  repeat
    local data, err = s:read(4096)
    if data then
      output:write(data)
    else
      s:close()
      return
    end
  until false
end


local function computeValue(o, args, key)
  local errMsg
  if not o.isPure then
    local r1, w1 = xpio.pipe()
    local r2, w2 = xpio.pipe()

    if not config.silent then
      w1:write('==> ' .. o.name .. '(')
      for i=1,#args do
        w1:write(serializeSorted(args[i]))
        if i ~= #args then
          w1:write ','
        end
      end
      w1:write(')\n')
    end

    local cfg = {
      quiet    = config.quiet,
      silent   = config.silent,
      buildDir = config.buildDir .. '/' .. key,
      io       = {[1]=w1, [2]=w2},
      outPath  = o.outPath, -- Preferred output path
    }

    local ok, err, val = xpcall(o.func, debug.traceback, cfg, table.unpack(args))
    if ok then
      if err ~= nil then
        errMsg = err
        o.value = false
      else
        o.value = val
        o.valid = true
        if not config.silent then
          w1:write('--> ' .. serializeSorted(o.value) .. '\n\n')
        end
      end
    end
    w1:close()
    w2:close()
    pipeAllToFile(r1, io.stdout)
    pipeAllToFile(r2, io.stderr)
    if not ok then
      error(err)
    end
  else
    local oldDir = xpfs.getcwd()
    chdir(o.dir)
    o.value = o.func(table.unpack(args))
    chdir(oldDir)
    o.valid = true
  end

  return errMsg, o.value
end

local function readFile(p)
  local f = assert(io.open(p, 'rb'))
  local s = f:read('*a')
  f:close()
  return s
end

-- Return the sha1 checksum for the file at the given path
local function digestFile(p)
  local s = readFile(p)
  return sha1.digest(s)
end

local function mkBuildName(db, nm)
   db.builders = db.builders or {}
   db.builders[nm] = db.builders[nm] or {lastIndex = 0}
   local i = db.builders[nm].lastIndex + 1
   db.builders[nm].lastIndex = i
   return nm .. '/' .. i
end

local function sparkIO(o, args, compute)
  local value
  local argsString = serializeSorted(args)

  -- Serialize the args and q unique ID for the function.
  local key = o.name .. '/' .. sha1.digest(argsString)

  local oldDir = xpfs.getcwd()
  local database = chdir(o.dir)

  local stale = nil

  -- Check to see if the input arguments have changed
  --
  -- If a getInputFiles function is provided, it should
  -- return a list of dependencies or nil.  If nil,
  -- we assume this function changes "something", but
  -- it won't tell us what, and we therefore always
  -- recompute.  If no getInputFiles function is given,
  -- we assume this is a pure function and does no I/O.
  local dbEntry = database.results[key]
  if dbEntry == nil or dbEntry.valid == nil then
    stale = {}
    dbEntry = dbEntry or {}

    dbEntry.buildName = dbEntry.buildName or mkBuildName(database, o.name)

    local cfg = {} -- TODO: Is there any value in populating this.
    local inputFiles = o.info.getInputFiles and o.info.getInputFiles(cfg, table.unpack(args))
    if inputFiles then
      dbEntry.sources = {}
    end
    for _,v in ipairs(inputFiles or {}) do
      if not xpfs.stat(v) then
        chdir(oldDir)
        return "File not found '" .. v .. "'."
      end
      stale[v] = digestFile(v)
    end
  else
    -- Metatable is not serialized.  So add that here.
    local mt = o.info.outputMetatable
    if mt and dbEntry.valid then
      setmetatable(dbEntry.value, mt)
    end
  end

  if dbEntry.sources then
    for k,v in pairs(dbEntry.sources) do
      -- Lookup sha1 from cache
      if not xpfs.stat(k) then
        chdir(oldDir)
        return "File not found '" .. k .. "'."
      end
      local hash = digestFile(k)

      if v ~= hash then
        stale = stale or {}
        stale[k] = hash
      end
    end
  else
    -- If getInputFiles returned nil, dbEntry.sources will be nil,
    -- which means ALWAYS recompute
    stale = stale or {}
  end

  if stale then
    local function computeAndSave()
      dbEntry.valid = false
      database.results[key] = dbEntry
      local ok, err, val = xpcall(compute, debug.traceback, o, args, dbEntry.buildName)
      if ok and err == nil then
        dbEntry.value = o.value
        dbEntry.valid = true
        for k,v in pairs(stale) do
          dbEntry.sources[k] = v
        end
        save(database)
        return nil, val
      else
        -- On failure, mark the previous result as invalid.
        database.results[key].valid = nil
        save(database)
        if ok then
          return err
        else
          error(err) -- Re-throw
        end
      end
    end
    value = thread.new(computeAndSave)
  else
    value = dbEntry.value
    o.value = value
    o.valid = true
  end
  chdir(oldDir)

  return nil, value
end

-- Either fetch a cached value or spark a thread that returns
-- a cached value.
function spark(o, compute)
  compute = compute or computeValue
  local err, value
  if not o.valid then
    local args
    err, args = lower(o.args, compute)
    if err == nil then
      if config.cache and not o.isPure then
        err, value = sparkIO(o, args, compute)
      else
        value = thread.new(compute, o, args, o.name)
      end
    end
  else
    value = o.value
  end

  -- Uncomment this for serial evaluation
  --if isTask(value) then
  --  err, value = thread.join(value)
  --end

  return err, value
end

local function builder(f, name, info, isPure, args)
  local priv = {
    dir     = xpfs.getcwd(),
    func    = f,
    name    = name,
    info    = info,
    isPure  = isPure,
    outPath = nil,
    args    = args,
  }
  local t = {
    _priv = priv,
  }
  return setmetatable(t, builderMeta)
end

local function flatten(t, o)
  o = o or {}
  for _, v in pairs(t) do
    if type(v) == 'table' then
      flatten(v, o)
    else
      table.insert(o, v)
    end
  end
  return o
end

local function defaultGetInputFiles(...)
  local vs = flatten{...}
  local fs = {}
  for _,v in ipairs(vs) do
    if type(v) == 'string' then
      local x = xpfs.stat(v)
      if x and x.kind == 'f' then
        table.insert(fs, v)
      end
    end
  end
  return fs
end

local function lift(f, name, info)
  info = info or {}
  info.getInputFiles = info.getInputFiles or defaultGetInputFiles
  return function(...)
    return builder(f, name, info, false, {...})
  end
end

local function liftPure(f, name)
  return function(...)
    return builder(f, name, {}, true, {...})
  end
end

local function liftEach(funcs, moduleName, liftFunc)
  local lifted = {}
  for k,v in pairs(funcs) do
    if type(v) == 'function' and type(k) == 'string' and not k:match('__info$') then
      lifted[k] = liftFunc(v, moduleName..'.'..k, funcs[k..'__info'])
    else
      lifted[k] = v
    end
  end
  return lifted
end

local function getBuildDirectory()
  return config.buildDir
end

local function clearCache()
  dbOfDatabases[xpfs.getcwd()] = {results = {}}
end

local function requireBuilders(nm)
  local xs = require(nm)
  return liftEach(xs, nm, lift)
end

local function requireWrapped(nm)
  local xs = require(nm)
  local wrapped = {}
  for k,f in pairs(xs) do
    if type(f) == 'function' and type(k) == 'string' and not k:match('__info$') then
      local key = nm..'.'..k
      local r1, w1 = xpio.pipe()
      local r2, w2 = xpio.pipe()
      local cfg = {
        quiet    = config.quiet,
        silent   = config.silent,
        buildDir = config.buildDir .. '/' .. key,
        io       = {[1]=w1, [2]=w2},
      }
      wrapped[k] = function(...)
        local err, v = f(cfg, ...)
        assert(not err, err)
        return v
      end
      w1:close()
      w2:close()
      pipeAllToFile(r1, io.stdout)
      pipeAllToFile(r2, io.stderr)
    end
  end
  return wrapped
end

local function requirePureBuilders(nm)
  local xs = require(nm)
  return liftEach(xs, nm, liftPure)
end

local function adjustPathIO(x, baseDir)
  if type(x) == 'string' then
    local p = lfsu.cleanpath(baseDir .. '/' .. x)
    return xpfs.stat(p) and p or x
  elseif type(x) == 'table' then
    local t = setmetatable({}, getmetatable(x))
    for k,v in pairs(x) do
      t[k] = adjustPathIO(v, baseDir)
    end
    return t
  end
end

local adjustPath = liftPure(adjustPathIO, 'flake.adjustPathIO')


local function adjustAndEvaluate(x, path, evaluate)
  if isBuilder(x) then
    x = adjustPath(x, path)
    if evaluate == true then
      local err, v = lower(x)
      if err ~= nil then
        error(err)
      end
      return v
    end
    return x
  elseif type(x) == 'table' then
    local t = setmetatable({}, getmetatable(x))
    for k,v in pairs(x) do
      t[k] = adjustAndEvaluate(v, path, evaluate)
    end
    return t
  elseif type(x) == 'string' then
    return adjustPathIO(x, path)
  end
end

-- Normalize the user's arguments
local function validate(path, spec, ps)
  ps = list.clone(ps or {})
  for k,v in pairs(spec) do
    local x = ps[k]
    if x ~= nil then
      -- If the parameter is a path, make it relative to the target directory.
      if v.type == nil or v.type == 'path' then
        x = adjustAndEvaluate(x, path, true)
      end
      -- If the parameter value not one of the values in the spec, bail out.
      if #v > 0 and list.find(v, x) == nil then
        io.stderr:write('flake: \'' .. x .. '\' is not a valid value for \'' .. k .. '\'\n')
        os.exit(1)
      end
    else
      ps[k] = v.default
    end
  end
  return ps
end

local function importBuild(path, evaluate)
  local f = assert(loadfile(path .. '/build.lua'))

  local oldDir = xpfs.getcwd()
  chdir(path)

  local absDir = xpfs.getcwd()
  local o = assert(f())

  chdir(oldDir)

  if not isBuilder(o) and type(o) == 'table' then
    for k,func in pairs(o) do
      if type(func) == 'function' then
        o[k] = function(...)
          local oldDir = xpfs.getcwd()
          chdir(absDir)

          local args = {...}
          if o.params then
            args = {validate(oldDir, o.params, ...)}
          end

          local t = table.pack(func(table.unpack(args)))

          chdir(oldDir)

          t = adjustAndEvaluate(t, path, evaluate)
          return table.unpack(t)
        end
      end
    end
  end

  return o
end

local function importBuilt(path)
  return importBuild(path, true)
end

-- Override lib[nm] with a function that recursively lowers
-- the first arugment of lib[nm] until it is not a builder.
local function decendThenCall(lib, nm)
  local f = lib[nm]
  lib[nm] = function(t)
    if isBuilder(t) then
      local err, t = decend(t)
      if err ~= nil then
        error(err)
      end
      return lib[nm](t)  -- recurse until the result is not a builder
    else
      return f(t)
    end
  end
end

-- Pass operators on builders to their output values
local operatorBuilders = liftEach(operator, 'operator', liftPure)
for k, v in pairs(operatorBuilders) do
  builderMeta['__' .. k] = v
end

builderMeta.__newindex = function(t,k,v)
  error 'setting a field on a builder object is not permitted'
end

builderMeta.__pairs = function(t)
  error 'calling "pairs" on a builder object is not permitted'
end

builderMeta.__ipairs = function(t)
  error 'calling "ipairs" on a builder object is not permitted'
end

local function configure(ps)
  for k,v in pairs(ps) do
    config[k] = v
  end
  if config.silent then
    config.quiet = true
  end
  initDatabase()
end

initDatabase()

return {
  clearCache            = clearCache,
  computeValue          = computeValue,
  configure             = configure,
  decend                = decend,
  decendThenCall        = decendThenCall,
  defaultGetInputFiles  = defaultGetInputFiles,
  getBuilders           = getBuilders,
  getBuildDirectory     = getBuildDirectory,
  importBuild           = importBuild,
  importBuilt           = importBuilt,
  isBuilder             = isBuilder,
  lift                  = lift,
  liftPure              = liftPure,
  liftEach              = liftEach,
  lower                 = lower,
  requireBuilders       = requireBuilders,
  requirePureBuilders   = requirePureBuilders,
  requireWrapped        = requireWrapped,
  spark                 = spark,
  validate              = validate,
}
