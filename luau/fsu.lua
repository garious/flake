-- fsu.lua : File System Utilities
--
-- This is a collection of file utility functions that use only standard Lua
-- API functions.  Use the "lfsu" module for additional functions that
-- require LFS.
--
-- Functions
-- =========
--
-- Without LFS, FSU cannot detect the underlying OS, so it provides two
-- versions of some functions. `fsu.win` holds versions suitable for
-- Windows, `fsu.nix` holds versions suitable for UNIX systems.
--
-- cleanpath(path)  -->  path
--
--    Remove redundant "." and "dir/.." segments from the path.  Initial
--    ".." elements will be retained.  Redundant trailing "/" is trimmed.
--    In Windows, convert slashes to "/".
--
-- splitpath(path)  -->  dir, name
--
--    Given path, return parent directory and name within that directory.
--    If there are no directory separators, return ".".  Any ".." or "."
--    elements in the input are treated as significant (cleanpath() is not
--    called).  Slashes are normalized (Windows).
--
--    If `path` is relative and includes no directory separators, the `dir`
--    result is ".".  If `path` identifies a root directory, `dir` is the
--    root directory and `name` is ".".
--
-- resolve(dir, path)  -->  path
--
--    Combine directory name with a path relative to it, returning a "clean"
--    path.  Example:  resove("a/b", "../c") --> "a/c".
--
-- relpathto(src, dst, [cwd]) --> path
--
--    Compute a relative path to `dst` as if `src` were the current working
--    directory.  Returned path has no trailing slash unless its a root
--    directory.  In Windows, returned path has forward slashes, and result
--    may be absolute when drive letters differ between `src` and `dst`.  If
--    `src` or `dst` are relative and `cwd` is supplied, `cwd` indicates the
--    directory to which they are relative.
--
--    If `src` is an absolute path and `dst` relative, `cwd` is needed to
--    successfully construct a result (an error results otherwise).
--
--    If `src` is relative and `dst` absolute, `cwd` is needed to construct
--    a relative path (an absolute path is returned otherwise).
--
--    If `src` begins with more ".." elements than `dst` (after both have
--    been resolved with `cwd`, if given), then an error results.
--
--    On error, relpathto() returns nil and an error string.
--
-- read(filename)  -->  data, [error]
--
--    Return file contents, or nil and error string.
--
-- write(filename, data)  -->  success, [error]
--
--    Write contents to file.
--
-- File Name Conventions
-- =====================
--
-- Returned directory names do not have trailing slashes unless they
-- identify a root directory (e.g. "/" or "C:/").  Input strings naming
-- directories *may* include a trailing slash for non-root directories.
--
-- `win` functions accept forward- or backslashes, recognize drive letters,
-- perform case-insensitive comparisons (but preserve case), and return
-- paths with forward slashes.
--
-- `nix` functions recognize only "/" as a directory separator and perform
--  case-sensitive comparisions.
--

----------------------------------------------------------------
-- Shared functions
----------------------------------------------------------------

local function addslash(p)
   if p:sub(-1) == "/" then
      return p
   end
   return p .. "/"
end


-- Split "dir/name" into "dir" and "name".  Root dir = "/"
--
local function splitpath(path)
   if path:sub(-1) == "/" then
      path = path:sub(1,-2)
   end
   local dir, name = path:match("(.*)/(.*)")
   if dir then
      return (dir=="" and "/" or dir), name
   elseif path == "" then
      return "/", "."
   end
   return ".", path
end


-- Eliminate "." and ".." where possible, and normalize path:
--  * Use only "/" as a separator character.
--  * No trailing "/", except in the case of the root directory
--  * No "." elements, except in the case of a solitary "."
--  * No ".." elements, except at the start of the path.
--
local function cleanpath(path)
   local init, path = path:match("^(/*)(.*)")

   while path:sub(1,2) == "./" do
      path = path:sub(3)
   end

   local e,post
   local n = 1
   repeat
      n, e, post = path:match("/()(%.%.?)(.?)", n)
      if post ~= "" and post ~= "/" then
         -- skip
      elseif e == "." then
         -- "xxx" /. "/yyy" => "xxx/yyy"
         path = path:sub(1,n-2) .. path:sub(n+1)
         n = n - 1
      else
         --  "xxx/" parent/../ "yyyy"  -> "xxx/yyy"
         local a = n-2
         while a > 0 and path:sub(a,a) ~= "/" do
            a = a - 1
         end
         local parent = path:sub(a+1,n-2)
         if parent ~= "" and parent ~= ".." then
            path = path:sub(1,a) .. path:sub(n+3)
            n = a
         end
      end
   until n == nil

   -- no trailing '/'
   if path:sub(-1,-1) then
      path = path:match("(.-)/*$")
   end

   path = init .. path
   return path ~= "" and path or "."
end


-- Compute relative from directory `src` to directory `dst`.  `src` and
-- `dst` must be absolute, clean paths.  Result is always a relative path,
-- or nil if src begins with ".." elements.
--
local function xrelpathto(src, dst, streq)
   local s = addslash(src)
   local d = addslash(dst)

   while true do
      local a, b = s:match("[^/]*/"), d:match("[^/]*/")
      if not a then
         break
      elseif streq(a,b) then
         s = s:sub(#a+1)
         d = d:sub(#a+1)
      elseif a == "../" then
         return nil, "relpathto: destination is above root directory"
      elseif a == "/" then
         return nil, "relpathto: no base for destination directory"
      elseif b == "/" then
         break   -- absolute from relative?
      else
         s = s:sub(#a+1)
         d = "../" .. d
      end
   end
   d = d:sub(1,-2)
   return d == "" and "." or d
end


local function read(name)
   local f,err = io.open(name, "r")
   if not f then
      return f,err
   end
   local data = f:read("*a")
   f:close()
   return data
end


local function write(name, data)
   local f,err = io.open(name, "wb")
   if not f then
      return f,err
   end
   f:write(data)
   f:close()
   return true
end


----------------------------------------------------------------
-- UNIX functions
----------------------------------------------------------------

local nix = {
   read = read,
   write = write,
   cleanpath = cleanpath,
   splitpath = splitpath,
}


local function streq(a,b)
   return a==b
end


function nix.resolve(dir, path)
   if path:sub(1,1) == "/" then
      --
   else
      path = addslash(dir) .. path
   end
   return cleanpath(path)
end


function nix.relpathto(src, dst, cwd)
   if cwd then
      src = nix.resolve(cwd, src)
      dst = nix.resolve(cwd, dst)
   end
   return xrelpathto(src, dst, streq)
end


----------------------------------------------------------------
-- Windows functions
----------------------------------------------------------------

local function splitdev(path)
   local drv, rest = path:match("^([a-zA-Z]%:)(.*)")
   return drv, rest or path
end


local function joindev(drive, path)
   return drive and drive..path or path
end


local function streqi(a,b)
   return a==b or a and b and a:upper()==b:upper()
end


local function fixslashes(path)
   return path:gsub("\\", "/")
end


local win = {
   read = read,
   write = write,
}

function win.cleanpath(path)
   local drv, p = splitdev( fixslashes(path) )
   return joindev(drv, cleanpath(p))
end


function win.splitpath(path)
   local drv, x = splitdev( fixslashes(path) )
   local xdir, xpath = splitpath(x)
   return joindev(drv, xdir), xpath
end


function win.resolve(dir, path)
   if path:match("^[a-zA-Z]:[/\\]") then
      --
   elseif path:match("^[/\\]") then
      path = joindev(dir:match("^([a-zA-Z]:)"), path)
   else
      path = addslash(dir) .. path
   end
   return win.cleanpath(path)
end

function win.relpathto(src, dst, cwd)
   if cwd then
      src = win.resolve(cwd, src)
      dst = win.resolve(cwd, dst)
   end

   local sd, sp = splitdev(src)
   local dd, dp = splitdev(dst)
   if streqi(sd, dd) then
      return xrelpathto(sp, dp, streqi)
   end
   return dst
end

----------------------------------------------------------------

return {
   nix = nix,
   win = win,
}
