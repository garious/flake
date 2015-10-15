-- xpexec.lua : cross-platform command execution
--
-- This module provides functions for constructing a command line to be
-- passed to os.execute/io.popen, quoting command arguments in a manner
-- appropriate for the underlying shell or OS so that spaces and/or special
-- characters will be passed uncorrupted to the invoked program.  Windows
-- (with the CMD.EXE shell) and other platforms (with sh, bash, or other
-- POSIX-like shells) are supported.
--
-- Note that shell syntax such as ">", "|", "&" or ";", should not be
-- escaped using these quoting functions.


-- Quote a command argument for UNIX-like environments.
--
local function quoteArgNix(arg)
   if arg:match("[!\"#%$&'%(%)%*;<>%?%[\\%]`{|}~%s]") then
      arg = "'" .. arg:gsub("[']", "'\\''") .. "'"
   end
   return arg
end


-- Quote a command argument for CMD.EXE.
--
-- Windows passes a single string of arguments to new processes, not an
-- array of zero-terminated strings.  For programs that use main(argc,argv),
-- the runtime is responsible for parsing the string into arguments before
-- calling main().  An MSDN article on "Parsing C Command-Line Arguments"
-- for Visual Studio describes MS C runtime behavior.  This specifies a
-- means of escaping double quotes within an argument using backslashes.
--
-- *Before* the runtime sees the command string, CMD.EXE processes it.  It
-- treats `"%&()<>|^` as having special meaning and does not pass them
-- through, unless they are escaped with a `^` character.  CMD looks for
-- double quotes and treats everything within a pair of quotes as literals,
-- so special characters within double quotes should *not* be escaped.
-- Interestingly, though: (a) the quotes themselves are passed through to
-- the runtime, (b) it provides no way to escape quotes within quotes, and
-- (c) it does not understand backslash-escaping, so quotes escaped for the
-- runtime will toggle CMD's quoted/unquoted state (unless the quotes
-- themselves are escapes with `^`).  Unbalanced quotes escaped for the
-- runtime would then cause problems elsewhere on the command line.
--
-- To avoid confusion we `^`-escape all CMD specials, including `"`,
-- whenever a quote character appears in the argument.
--
-- In the simpler case where the string includes no quote characters, we can
-- simply rely on double quotes and not escape CMD specials.
--
-- And in the simplest case, where no special characters or spaces occur, we
-- can avoid quotes entirely.
--
-- Finally, CMD will terminate the command name (the first word on the
-- command line) at "/", so "/" characters are quoted as well in that case.
--
local function quoteArgWin(arg, first)
   local result = arg

   -- use quotes if argument contains specials or spaces
   if arg:match('[%s%%&%(%)<>%^|]') or first and arg:match("/") then
      result = '"' .. arg:gsub('(\\*)"', '\\%1%1"') .. '"'
   end

   -- escape specials if argument contains a '"'
   if arg:match('"') then
      result = result:gsub('["%%&%(%)<>%^|]', '^%1')
   end

   return result
end


-- The behavior of "echo" indicates whether the underlying shell/platform is
-- CMD.EXE.  Since this is a built-in in CMD, sh, and bash this should
-- be immune to other environment differences.
--
local bWindows
local function isWindows()
   if bWindows == nil then
      local p = io.popen("echo", "r")
      if p then
         local out = p:read("*a")
         p:close()
         bWindows = (out and out:match("ECHO is")) ~= nil
      end
   end
   return bWindows
end


-- Traverse tree in-order, appending f(<string>) to o[] for each string.  If
-- a table has a "raw" field, its string descendants will be appended
-- without f() being applied.
--
local function visitAndAppend(results, t, f)
   if t.raw then
      f = nil
   end
   for _,v in ipairs(t) do
      if type(v) == "table" then
         visitAndAppend(results, v, f)
      else
         if f then v = f(v, #results==0) end
         table.insert(results, v)
      end
   end
end


-- Construct a command string appropriate for os.execute().
--
-- Parameters of type "string" are individually quoted.  Parameters of type
-- "table" are expanded in place, recursively, with their members being
-- individually quoted.
--
-- A table with a 'raw' field set contains strings that are NOT to be quoted
-- (e.g. '>' when used for redirection).
--
-- For example (assuming UNIX):
--
--   quoteCmd("a", "&")               -->   "a '&'"
--   quoteCmd("a", {raw=true, "&"})   -->   "a &"
--   quoteCmd("a", {}, {{"&"}})       -->   "a '&'"
--
local function quoteCommand(...)
   local args = {}
   visitAndAppend(args, {...}, isWindows() and quoteArgWin or quoteArgNix)
   local cmd = table.concat(args, " ")

   -- In Windows, os.execute() calls system(), which will munge the string
   -- (*prior* to all of the CMD processing described above in quoteArg)
   -- unless we put '"' at the start and end of the command string.

   if isWindows() and cmd:sub(1,1) == '"' then
      cmd = '"' .. cmd .. '"'
   end
   return cmd
end


local function quoteArg(a)
   local f = isWindows() and quoteArgWin or quoteArgNix
   return f(a)
end


return {
   quoteCommand = quoteCommand,
   quoteArg = quoteArg,
   quoteArgNix = quoteArgNix,
   quoteArgWin = quoteArgWin,
   isWindows = isWindows,
}
