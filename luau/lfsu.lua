-- lfsu.lua
--
-- This module extends "fsu" with functions that require the "xpfs" module.
-- It selects the set of functions appropriate for the underlying OS and
-- returns one table with both the FSU functions and the additiona LFSU
-- functions.
--
-- Functions
-- =========
--
-- In addition to the functions defined in fsu, this module implements:
--
-- abspath(path)  -->  path
--
--    Given an absolute or relative path, construct an absolute path.
--    On windows, the result users only forward slashes.
--
-- relpathto(src, dst, cwd) --> path
--
--    This behaves as defined in fsu, except `cwd` defaults to
--    xpfs.getcwd()
--
-- mkdir_p(path)  -->  success, [error]
--
--    Create directory, creating intermediate directories as needed,
--    as "mkdir -p" does.  Returns true on success; nil, error otherwise.
--
-- rm_rf(path)  -->  success, [error]
--
--    Delete file/directory `path`, deleteing sub-directories if necessary.
--

local xpfs = require "xpfs"
local fsu = require "fsu"

local iswin = xpfs.getcwd():match("^[a-zA-Z]%:\\")
local base = iswin and fsu.win or fsu.nix

local U = setmetatable({}, { __index = base })

U.iswindows = iswin


function U.relpathto(src, dst, cwd)
   return base.relpathto(src, dst, cwd or xpfs.getcwd())
end


function U.abspath(path)
   return base.resolve(xpfs.getcwd(), path)
end


local function _mkdir_p(dir, split)
   local e,m = true

   local st = xpfs.stat(dir, "k")
   if not st then
      local p = split(dir)
      if p == dir then
         return nil, "unexpected error: " .. dir .. " does not exist"
      end
      e, m = _mkdir_p(p, split)
      if e then
         e, m = xpfs.mkdir(dir)
      end
   elseif st.kind ~= "d" then
      e,m = nil, "could not create directory "..dir
   end
   return e,m
end

function U.mkdir_p(path)
   return _mkdir_p(path, base.splitpath)
end


function U.rm_rf(name)
   local s,e = true

   local todo = { name }
   while #todo > 0 do
      local f = table.remove(todo)
      if type(f) == "table" then
         s,e = xpfs.rmdir(f[1])
         if not s then break end
      else
         local st = xpfs.stat(f, "k")
         if st and st.kind == "d" then
            table.insert(todo, {f})
            local de = xpfs.dir(f)
            for _, g in ipairs(de) do
               if g ~= "." and g ~= ".." then
                  table.insert(todo, f .. "/" .. g)
               end
            end

         else
            s,e = xpfs.remove(f)
            if not s then break end
         end
      end
   end

   return s,e
end


return U
