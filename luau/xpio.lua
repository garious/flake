-- xpio
--
-- The `xpio` library has native and Lua components.  This "top" package
-- (this one) obtains the native library and injects additional functions
-- into the `xpio` table and some of the metatables that it uses.

local xpio = require "xpio_c"
local xpfs = require "xpfs"

local yield = coroutine.yield

local currentTask

local dirSep = package.config:sub(1,1)
local pathSep = dirSep == "/" and ":" or ";"

--------------------------------
-- socket metatable extensions
--------------------------------

local Socket = xpio._XPSocket


-- write *all* of the data before returning
--
function Socket:write(data)
   local amt = 0
   while data ~= "" do
      local num, err = self:try_write(data)
      if num then
         amt = amt + num
         data = data:sub(num+1)
      elseif err ~= "retry" then
         return nil, err
      else
         yield( self:when_write(currentTask) )
      end
   end
   return amt
end


function Socket:read(amt)
   repeat
      local a, b = self:try_read(amt)
      if a then
         return a
      elseif b ~= "retry" then
         return nil, b
      end
      yield( self:when_read(currentTask) )
   until false
end


function Socket:connect(...)
   repeat
      local succ, err = self:try_connect(...)
      if succ or err ~= "retry" then
         return succ, err
      end
      yield( self:when_write(currentTask) )
   until false
end


function Socket:accept()
   repeat
      local s, err = self:try_accept()
      if s then
         return s
      end
      if err ~= "retry" then
         return nil, err
      end
      yield( self:when_read(currentTask) )
   until false
end


--------------------------------
-- process metatable extensions
--------------------------------


local Process = xpio._XPProc


function Process:wait()
   repeat
      local a, b = self:try_wait()
      if a == nil and b == "retry" then
         yield( self:when_wait(currentTask) )
      else
         return a, b
      end
   until false
end


--------------------------------
-- xpio extensions
--------------------------------


function xpio.setCurrentTask(task)
   currentTask = task
end


function xpio.getCurrentTask(task)
   return currentTask
end


-- fdjuggle(fdmap, nextfd) -> commands
--
-- Construct a sequence of dup2 and close commands that produce a given
-- set of descriptors for a child process.
--
-- On entry:
--
--   fdmap: table mapping childFD -> parentFD.  Each value (parentFD)
--          identifies a currently-open file.  Each key (childFD) is a
--          descriptor where the file will appear in the child's FD set.
--          Descriptors not named as keys will be closed in the child
--          process.
--
--   nextfd() = iterator of all currently-open file descriptors.
--
-- Return value = array of {fdTo, fdFrom}.  When fdFrom is nil, fdTo is to
--                be closed.  Otherwise, it describes a dup2() operation.
--
-- Complexity arises from the potential for loops (e.g.  1->2 and 2->1).  In
-- order to avoid clobbering descriptors that we will later need, we
-- identify chains, and iterate from the "heads" of chains (FDs that will be
-- dup'ed over, and have no references to them, and therefore will not
-- survive the spawn). Starting at heads, we can follow the chain, dup'ing
-- until we reach (a) the end, or (b) a descriptor that we have already
-- dup'ed.  (For each dup, we keep track of the destination descriptor.)
-- Then we have to deal with cycles that have no pointers from the outside;
-- we do this by creating a temporary 'head' FD, processing the chain, and
-- then closing the temporary FD.
--
-- Cases to deal with:
--
--    fdmap = {[1]=2, [2]=1, [3]=2, [4]=2, [5]=6, [7]=8, [8]=7, [9]=9}
--
--
--    4 <--+              5 <- 6
--         |
--         |
--    3 <- 2 --+
--         ^   |
--         |   v
--         +-- 1
--
--    7 --+      9 --+
--    ^   |      ^   |
--    |   v      |   |
--    +-- 8      +---+
--
--
--
-- `nextfd` supports iterating all of the open descriptors in the process
-- that are not marked "close on exec". It is an iterator like Lua's `next`.
--
local function fdjuggle(_fdmap, nextfd)
   local o = {}

   local function dup2(from, to)
      o[#o+1] = { to, from }
   end

   local function close(fd)
      o[#o+1] = { fd }
   end

   local to = {}
   local from = {}
   for dest, src in pairs(_fdmap) do
      src = tonumber(src) or src:fileno()
      to[dest] = src
      from[src] = true
   end

   local newnames = {}
   local tmpfd

   local function dupChain(a, b)
      if not b then
         close(a)
      elseif newnames[b] then
         -- b already vsited
         dup2(newnames[b], a)
      else
         -- b not yet visited; continue along chain
         dup2(b, a)
         newnames[b] = a
         return dupChain(b, to[b])
      end
   end

   -- close unreferenced FDs
   for a in nextfd do
      if not to[a] and not from[a] then
         close(a)
      end
   end

   -- visit chains
   for a, b in pairs(to) do
      if not from[a] then
         dupChain(a, b)
      end
   end

   -- visit cycles
   for a, b in pairs(to) do
      if a == b then
         dup2(a, b)
      elseif from[a] and not newnames[a] then
         if not tmpfd then
            tmpfd = 0
            while to[tmpfd] do
               tmpfd = tmpfd + 1
            end
         end
         dupChain(tmpfd, a)
      end
   end

   if tmpfd then
      close(tmpfd)
   end

   return o
end


local function searchPath(file)
   local path = os.getenv("PATH") or ""
   for dir in (path .. pathSep):gmatch("(.-):") do
      if dir == "" then
         dir = "."  -- legacy UNIX behavior
      end
      local path = dir .. dirSep .. file

      -- We could make this really complicated, as BASH does, but instead
      -- let's return the first matching file with an executable bit set.
      local stat = xpfs.stat(path, "pk")
      if stat and stat.kind == "f" and stat.perm:match("x") then
         return path
      end
   end
end


function xpio.spawn(args, env, files, attrs)
   local file = assert(attrs and attrs.exe or args[1], "spawn: file not provided")

   if not file:match(dirSep) then
      file = assert(searchPath(file), "file not found in PATH")
   end

   local fdActions = fdjuggle(files, xpio._nextfd)

   local envStrings = {}

   for k, v in pairs(env) do
      envStrings[#envStrings+1] = k .. "=" .. v
   end

   local proc = xpio._spawn(file, args, envStrings, fdActions)

   -- close granted file objects
   for _, socket in pairs(files) do
      if type(socket) == "userdata" then
         socket:close()
      end
   end

   return proc
end


-- export for testing
xpio._fdjuggle = fdjuggle
xpio._searchPath = searchPath

return xpio
