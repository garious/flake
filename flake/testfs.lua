local xpfs   = require 'xpfs'
local lfsu   = require 'lfsu'

-- Table lookup where key can be the array part of the table.
-- If it is, return true, otherwise, return the value in the hash part.
local function lookup(t, k)
  local v = t[k]
  if v then
    return v
  end
  for _, v in ipairs(t) do
    if k == v then
      return true
    end
  end
  return nil
end

-- testfs.match(dirPath, dirSpec, isSpecASubset)
--
-- Check if a file structure matches the given specification.
--
-- Specification format:
--   * A directory is represented by a table, where the keys are filenames.
--        * If the value is 'true', the file must exist.
--        * If the value is a string, the files contents must match the string.
--        * If the value is a function, the files contents are passed the function.
--          The function should return true to indicate a match.
--   * A directory may be an array.  The following are equivalent specs:
--          {'a','b'} == {['a'] = true, ['b'] = true}
--
-- If 'subset' is true, that means the specification represents a
-- subset of the directory.  Therefore, ignore files in the directory
-- that are not in the specification.
local function match(dir, t, subset)
  local attrs, err = xpfs.stat(dir)
  if attrs == nil or attrs.kind ~= 'd' then
    return false, 'directory does not exist: '..dir
  end

  if not subset then
    -- First, verify that the given table contains an entry for each file in the root directory.
    for _, filename in ipairs(xpfs.dir(dir)) do
      if filename ~= '.' and filename ~= '..' then
        if lookup(t,filename) == nil then
          return false, "unexpected file '" .. filename .. "' found in '" .. dir .. "'"
        end
      end
    end
  end

  -- Next, verify each file in the given table has the expected contents.
  for k,v in pairs(t) do
    -- If table used as an array, only assert the file exists.
    if type(k) == 'number' then
      k, v = v, true
    end
    assert(type(k) == 'string')
    local path = dir == '' and k or dir..'/'..k
    if type(v) == 'table' then
      return match(path, v, subset)
    elseif type(v) == 'string' then
      if lfsu.read(path) ~= v then
        return false, 'file contents mismatch'
      end
    elseif type(v) == 'function' then
      if not v(lfsu.read(path)) then
        return false, 'file contents mismatch'
      end
    elseif type(v) == 'boolean' then
      local attrs, err = xpfs.stat(path)
      if attrs == nil or attrs.kind ~= 'f' then
        return false, 'file does not exist: ' .. path
      end
    else
      error("bad type for value of '"..k.."'.  expected 'string', 'table', or 'function' but got '"..type(v).. "'", 0)
    end
  end
  return true
end

return {
  match = match,
}

