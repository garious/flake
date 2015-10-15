local mt = {}

local function new(s)
  assert(type(s) == 'string')
  local p = {value = s}
  return setmetatable(p, mt)
end

local function isPath(p)
  return type(p) == 'table' and getmetatable(p) == mt
end

function mt.__tostring(p)    return p.value end
function mt.__eq(p1, p2)     return p1.value == p2.value end
function mt.__len(p)         return #p.value end
function mt.__concat(p1, p2)
  local p2Value = isPath(p2) and p2.value or p2
  return new(p1.value .. '/' .. p2Value)
end

-- Get the directory name, move up one level.
-- If a filename, returns '.'
local function takeDirectory(s)
  return s:match("(.*)/") or '.'
end

-- Get the file name.
local function takeFileName(s)
  return s:match('.+/(.*)$') or s
end

local function addExtension(p, s)
  assert(type(p) == 'string', type(p))
  assert(type(s) == 'string', type(s))
  if s ~= '' and s:sub(1,1) ~= '.' then
    s = '.' .. s
  end
  return p .. s
end

local function dropExtension(s)
  return s:match('(.+)%.') or s
end

local function replaceExtension(p, s)
  return addExtension(dropExtension(p), s)
end

-- Get the extension of a file, returns "" for no extension, .ext otherwise
local function takeExtension(s)
  local rExt = s:reverse():match('^([^%.]+%.)')
  return rExt and rExt:reverse() or ''
end

-- Get the base name, without an extension or path.
local function takeBaseName(s)
  return dropExtension(takeFileName(s))
end

return {
  new = new,
  isPath = isPath,
  takeBaseName = takeBaseName,
  takeDirectory = takeDirectory,
  takeFileName = takeFileName,
  addExtension = addExtension,
  dropExtension = dropExtension,
  replaceExtension = replaceExtension,
  takeExtension = takeExtension,
}

