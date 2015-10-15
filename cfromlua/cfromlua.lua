-- cfromlua: generate C program with main() from Lua sources

local usageString = [[
Usage:  cfromlua [options] FILE...

Options:
   -o FILE      : Output generated C source code to FILE.
   -l MOD       : Exe should load and run MOD before main module.
   -b MOD       : Bundle MOD even if it is not a dependency.
   -s MOD       : Skip MOD (do not bundle) even if it is a dependency.
   --path=PATH  : Add PATH to the Lua search path.
   --cpath=PATH : Add PATH to the C search path.
   --open=LIB   : Call luaopen_LIB() from generated C
   -I DIR       : Add "DIR/?.lua" to the search path.
   --minify     : Remove redundant characters when embedding sources.
   -w           : Display a warning when a required file cannot be found
                  (default = silently ignore)
   -Werror      : Treat warnings as errors (implies '-w')
   -MF FILE     : Write dependencies to FILE.
   -MP          : Add an empty dependency line for each included file.
   -MT TARGET   : Specify the target for the dependencies.
   -MX          : Include binary extensions in the dependency file.
   -m NAME      : Specify the main function name.
   --           : Stop processing options.
   -v           : Display module and file names as they are visited.
   -h,  --help  : Display this message.
   --readlibs   : Read library dependences from a generated C file.
   --win        : Use "\" when echoing library dependencies.

See cfromlua.txt for more information.
]]


----------------------------------------------------------------
-- utility functions
----------------------------------------------------------------
local progname = "cfromlua"
local options = {}


-- catch unintentional global usage
local mtG = {
   __newindex = function (t, k, v) error("Write to undefined global: " .. k, 2) end,
   __index = function (t, k) print(k); error("Read of undefined global: " .. k, 2) end
}
setmetatable(_G, mtG)


local function printf2(fmt, ...)
   io.stderr:write(string.format(progname .. ": " .. fmt, ...))
end


local function bailIf(cond, fmt, ...)
   if cond then
      printf2(fmt.."\n", ...)
      os.exit(1)
   end
end


local function warn(fmt, ...)
   if options.w then printf2("Warning: " .. fmt, ...) end
   if options.Werror then
      io.stderr:write("ERROR: warnings treated as errors\n")
      os.exit(1)
   end
end


local function vprintf(...)
   if options.v then printf2(...) end
end


local function basename(filename)
   return filename:match("(.*)%.[^%./\\]*$") or filename
end


local function dir(filename)
   return filename:match("(.*/)") or "./"
end


local function fileExists(name)
   local f = io.open(name, "r")
   if f then
      f:close()
      return name
   end
end


local function readFile(name)
   local f = io.open(name, "r")
   if f then
      local data = f:read("*a")
      f:close()
      return data
   end
end


local function writeFile(name, data)
   local f = name=="-" and io.stdout or io.open(name, "w")
   bailIf(not f, "Cannot open output file: %s", name)
   f:write(data)
   f:close()
   vprintf("wrote file '%s'\n", name)
end


-- Process options, returning unprocessed options and remaining arguments
--
local function getopts(args, o, errhandler)
   -- parse opts into table:  option -> { name=<string>, type=<string> }
   local opts = {}
   for desc in o:gmatch("([^%s]+)") do
      local names, type = desc:match("([^=]*)(=?%*?)$")
      assert(names)

      -- use first form as its canonical name
      local name = names:match("%-*([^/]*)")
      for opt in names:gmatch("([^/]+)/?") do
         opts[opt] = { name=name, type=type }
      end
   end

   local words, values = {}, {}
   local errfn = (type(errhandler) == "function" and errhandler or
               function (msg) error((errhandler or "getopts").. ": " .. msg) end)

   local function nextArg()
      return table.remove(args, 1)
   end

   for a in nextArg do
      local opt, optarg = a:match("^(%-%-[^=]*)=(.*)")
      if not opt then
         opt, optarg = a:match("^(%-.+)"), false
      end
      if not opt then
         table.insert(words, a)
      else
         local o = opts[opt]
         if o then
            local v = values[o.name]
            if o.type ~= "" then
               -- has an argument
               optarg = optarg or nextArg()
               if not optarg then
                  return errfn("Missing argument to "..opt)
               end
               if o.type:match("%*") then
                  v = v or {}
                  values[o.name] = v
                  table.insert(v, optarg)
               elseif not v then
                  values[o.name] = optarg
               else
                  return errfn("Argument repeated: " .. opt)
               end
            else
               -- no argument; just count
               values[o.name] = (v or 0) + 1
            end
         elseif opt == "--" then
            -- stop option processing
            for a in nextArg do
               table.insert(words, a)
            end
            break
         else
            return errfn("Unrecognized option: " .. a)
         end
      end
   end

   return words, values
end


-- Search LUA_PATH or LUA_CPATH. Does not implement ";;".
--
local function searchLuaPath(path, name)
   local repl = name:gsub("%.", "/")
   for p in path:gmatch("[^;]+") do
      local filename = p:gsub("%?", repl)
      if fileExists(filename) then
         return filename
      end
   end
end


local function ipairsIf(t)
   return ipairs(t or {})
end


----------------------------------------------------------------
-- minify
----------------------------------------------------------------

-- Parse Lua chunk, emitting stream of "plain", "string", and "comment" strings.
--
local function parse(txt, emit)
   local pos = 1            -- current position
   local pn                 -- beginning of next section
   local posend = #txt+1
   local ppos = {}   -- pattern -> position found (or #txt+1)

   local function find(pat)
      if (ppos[pat] or 0) < pos then
         ppos[pat] = txt:find(pat, pos) or posend
      end
      return ppos[pat]
   end

   local function produce(type)
      emit(type, txt:sub(pos, pn-1))
      pos = pn
   end

   local pS  = "[\"']"
   local pLS = "%[=*%["
   local pC  = "%-%-"
   local pLC = "%-%-%[=*%["

   while true do
      -- scan to next comment or string
      pn = math.min( find(pS), find(pLS), find(pC), find(pLC) )

      -- now: txt:(pos,pn-1) == plain
      if pn > pos then
         produce "plain"
      end

      -- now: pos == start of comment or string (or end)

      if pos == posend then
         return true
      elseif pos == ppos[pLS] then

         -- long string literal
         local eq = txt:match("%[(=*)%[", pos)
         assert(eq)
         pn = txt:match("%]"..eq.."%]()", pos)
         if not pn then
            return nil, "long string", pos
         end
         produce "string"

      elseif pos == ppos[pS] then

         -- regular string literal
         local q = txt:sub(pos,pos)
         local p = pos+1
         local pb
         repeat
            pb, pn = txt:match("()\\*"..q.."()", p)
            if not pn then
               return nil, "string", pos
            end
            p = pn
         until not pn or (pn - pb) % 2 == 1
         pn = pn or #txt
         produce "string"

      elseif pos == ppos[pLC] then

         -- long comment
         local eq = txt:match("%[(=*)%[", pos)
         assert(eq)
         pn = txt:match("%]"..eq.."%]()", pos)
         if not pn then
            return nil, "long comment", pos
         end
         produce "comment"

      elseif pos == ppos[pC] then

         -- single-line comment: includes "\n" unless at end of file
         pn = (txt:match("\n()", pos) or #txt+1)
         produce "comment"

      end
   end
end


-- Reduce comments to whitespace with equivalent number of line breaks
--
local function strip2(txt)
   local o = {}
   local c = {}

   local function emit(typ, str)
      if typ == "comment" then
         table.insert(c, str)
         str = str:gsub("[^\n]*", "")
         if str == "" then str = " " end
      elseif typ == "plain" then
         str = str:match("[ \t]*(.-)[ \t]*$")
         str = str:gsub("[ \t]+([^_%w])", "%1")
         str = str:gsub("([^%w_])[ \t]+", "%1")
         str = str:gsub("[ \t]+", " ")
      end
      table.insert(o, str)
   end

   local succ, err, pos = parse(txt, emit)
   if not succ then
      return nil, nil, err, pos
   end
   return table.concat(o), table.concat(c)
end


----------------------------------------------------------------

local quoteRepl = {
   ['\\'] = '\\\\',
   ['"']  = '\\"',
   ['\n'] = '\\n',
   ['\r'] = '\\r',
   ['\0'] = '\\0',
   ['?'] = '\\?'   -- avoid trigraphs (ugh)
}

local function toC(str)
   if type(str) == "string" then
      return '"' .. str:gsub('[\\"\n\r%?]', quoteRepl) .. '"'
   end
   return "0"
end


-- Lua's loadfile() skips the first line if it begins with "#", but
-- other methods of loading code do not, so we strip it here.
--
local function trimHash(src)
   return src:match("^#[^\n]*(.*)") or src
end


-- Outfile class
--
local Outfile = {}
Outfile.put = table.insert
function Outfile:fmt(...)
   self:put(string.format(...))
end
function Outfile:New()
   self.__index = self
   return setmetatable({}, self)
end



local ctemplate = [[
// Generated by cfromlua
#{impliedlibs}

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#define ARRAYLENGTH(a)   (sizeof(a) / sizeof(a[0]))

#{defs}

int luaopen_requirefile(lua_State *L);


typedef struct {
   const char *  pszName;      // module name
   const char *  pszSource;    // loadbuffer arg (location/source)
   const char *  pc;           // contents of file
   size_t        cb;           // size of pc[]
   lua_CFunction fn;           // C function
} BuiltIns;


// mods[0] = preamble
// mods[1] = main Lua source
// mods[2...] = source modules, native modules, or requirefiles
static const BuiltIns mods[] = { #{mods}
};


#{rfilesImpl}

int luaopen_requirefile(lua_State *L)
{
   lua_pushcfunction(L, &requirefile);
   return 1;
}


// ndx -> name, text
static int getModInfo(lua_State *L)
{
   size_t ndx = lua_tointeger(L, 1);
   if (ndx >= ARRAYLENGTH(mods)) {
      return 0;
   }

   lua_pushstring(L, mods[ndx].pszName);
   return 1;
}


// ndx --> function
static int getModFunc(lua_State *L)
{
   size_t ndx = lua_tointeger(L, 1);
   if (ndx >= ARRAYLENGTH(mods)) {
      return 0;
   }

   if (mods[ndx].fn) {
      lua_pushcfunction(L, mods[ndx].fn);
   } else if (!mods[ndx].pszSource) {
      return 0;
   } else if (luaL_loadbuffer(L, mods[ndx].pc, mods[ndx].cb, mods[ndx].pszSource)) {
      return lua_error(L);
   }
   return 1;
}


static int pmain(lua_State *L)
{
   int argc = lua_tointeger(L, 1);
   char **argv = (char **) lua_touserdata(L, 2);
   int n;

   lua_gc(L, LUA_GCSTOP, 0);
   luaL_openlibs(L);
   lua_gc(L, LUA_GCRESTART, 0);

   if (luaL_loadbuffer(L, mods[0].pc, mods[0].cb, mods[0].pszSource)) {
      return lua_error(L);
   }

   lua_createtable(L, argc-1, 1);        // argv
   for (n = 0; n < argc; ++n) {
      lua_pushstring(L, argv[n]);
      lua_rawseti(L, -2, n);
   }

   lua_pushcfunction(L, &getModInfo);    // getModInfo
   lua_pushcfunction(L, &getModFunc);    // getModFunc
   lua_pushliteral(L, #{preloads});      // preloads

   lua_call(L, 4, 1);

   return 1;
}


int #{main} (int argc, char **argv)
{
   int exitCode = EXIT_FAILURE;
   int nErr;
   lua_State *L;

   L = luaL_newstate();
   if (L == NULL) {
      fprintf(stderr, "lua_open failed: not enough memory\n");
      return EXIT_FAILURE;
   }

   lua_pushcfunction(L, &pmain);
   lua_pushinteger(L, argc);
   lua_pushlightuserdata(L, argv);
   nErr = lua_pcall(L, 2, 1, 0);

   if (nErr == LUA_ERRRUN) {
      fprintf(stderr, "pmain error:\n%s\n", lua_tostring(L, -1));
   } else if (nErr) {
      fprintf(stderr, "pmain failed: err = %d\n", nErr);
   } else if (lua_isnumber(L, 1)) {
      exitCode = lua_tointeger(L, 1);
   }

   lua_close(L);
   return exitCode;
}

]]


local rfilesEmpty = [[

static int requirefile(lua_State *L)
{
   (void) L;
   return 0;
}

]]


local rfilesNonEmpty = [[

typedef struct {
   const char * pszPath;      // requirefile path
   const char * pc;
   size_t       cb;
} RequireFiles;


static const RequireFiles rfiles[] = { #{rfiles}
};


// path --> contents
static int requirefile(lua_State *L)
{
   const char *path = lua_tostring(L, -1);
   size_t ndx;

   for (ndx = 0; ndx < ARRAYLENGTH(rfiles); ++ndx) {
      if (!strcmp(path, rfiles[ndx].pszPath)) {
         lua_pushlstring(L, rfiles[ndx].pc, rfiles[ndx].cb);
         return 1;
      }
   }
   return 0;
}

]]


-- preamble: By default, this is the first chunk executed by the program.
-- It is passed three arguments: argv, mods, preloads
--
--   mods[NAME] = function for module NAME
--   mods[1] is the main program
--
-- First it ensures that 'require' can find the built-in mods.  Then it
-- calls the second built-in module (the first user-supplied module) in a
-- manner compatible with how the default 'lua' executable would execute a
-- module, so the second module can expect:
--
--    ... = arguments 1..n
--    arg = arguments 1..n, plus arg[0] = argv[0]
--
local preamble = [=[
local argv, getModInfo, getModFunc, preloads = ...

-- Only the build-time paths should matter; not run-time. Erase these
-- to avoid accidental dependencies on the build environment.
package.path = ""
package.cpath = ""

local function start()
   -- populate preloads
   for n = 2, math.huge do
      local name = getModInfo(n)
      if not name then break end
      package.preload[name] = getModFunc(n)
   end

   -- load '-l' modules
   for m in preloads:gmatch("[^;]+") do
      require(m)
   end

   local main = getModFunc(1)
   arg = argv

   local unpack = table.unpack or unpack
   return main(unpack(argv))
end

local succ, v = xpcall(start, debug.traceback)
if not succ then
   print("Unhandled error: "..v)
   return 1
end
return tonumber(v) or 0

]=]


------------------------------------------------------------------------
-- Mod processing functions
------------------------------------------------------------------------

-- mods = array of:
--   mod.name      = package name if included via require, -l, or -b
--   mod.source    = description of source  [source modules]
--   mod.filename  = path to file           [source modules]
--   mod.arrayname = C name for array       [source modules]
--   mod.data      = file contents          [source modules]
--   mod.func      = function name          [native modules]
--   mod.libfile   = path to .lib           [native modules]
--
local mods = {}      -- modules (files & native libs) specified on command line
local path           -- search path for Lua modules (as in LUA_PATH)
local cpath          -- search path for native modules (as in LUA_CPATH)
local preloads = {}

-- knownMods = ignored, visited, or pre-packaged modules (do not search for them)
local knownMods = {
   string = true,
   debug = true,
   package = true,
   _G = true,
   io = true,
   os = true,
   table = true,
   math = true,
   coroutine = true
}


-- Find a module in the search path, if we haven't already.
--
local function findModule(name)
   local filename = searchLuaPath(path, name)
   if filename then
      return filename, readFile(filename)
   end

   filename = searchLuaPath(cpath, name)
   if filename then
      local base = basename(filename)
      local libfile = fileExists(base..".lib")
         or fileExists(base..".a")
         or fileExists(base..".o")
         or fileExists(base..".obj")

      if libfile then
         return libfile, nil
      end
      warn("%s found; %s missing\n", filename, libfile)
   end
end


local function addMod(m)
   vprintf("bundling %s\n", m.filename or m.func or m.name)
   table.insert(mods, m)
end


local function addLib(name, libfile)
   addMod {
      name = name,
      func = "luaopen_" .. name:gsub("%.", "_"),
      libfile = libfile
   }
end


local function isSlash(ch)
   return ch == "/" or ch == "\\"
end


local function join(a, b)
   if isSlash(b:sub(1,1)) then
      return b
   end
   local file = a .. (isSlash(a:sub(-1)) and "" or "/") .. b
   file = file:gsub("/%./", "/")
   return file
end


local function cfl_requirefile(path)
   local requirePath = os.getenv("REQUIREFILE_PATH") or "."

   local mod, rel = string.match(path, "([^/]+)/(.*)")
   bailIf(not mod, "cfromlua: requirefile: module name not given in '" .. path .. "'")

   local modFile = searchLuaPath(package.path, mod)
   bailIf(not modFile, "cfromlua: requirefile: module '" .. mod .. "' not found")

   local modDir = dir(modFile)
   for pathDir in requirePath:gmatch("([^;]+)") do
      local file = join( join(modDir, pathDir), rel)
      local data = readFile(file)
      if data then
         return data, file
      end
   end

   return nil
end


local rfiles = {}        -- array of { path=..., data=... }
local rfilesByMod = {}   -- rfiles[] indexed by module name

local function addRequireFile(mod)
   if rfilesByMod[mod] then return end
   rfilesByMod[mod] = true

   local data, filename = cfl_requirefile(mod)

   bailIf(not data, "cfromlua: requirefile: file does not exist '" .. mod .. "'")

   rfiles[#rfiles+1] = {
      mod = mod,
      data = data,
      filename = filename
   }
end


local addRequire

-- Add a source file to mods[] and follow its dependencies
--
local function addSource(name, filename, data)
   data = trimHash(data)
   local mini, comments, err, pos = strip2(data)
   if not mini then
      local lnum = select(2, data:sub(1,pos-1):gsub("\n","\n")) + 1
      bailIf(true, "%s:%d: syntax error: unterminated %s", filename, lnum, err)
   end

   addMod {
      name = name,
      filename = filename,
      data = options.minify and mini or data,
   }

   -- queue bundling of required files
   for func, mod in mini:gmatch("([%w%.:]-requiref?i?l?e?) *%(? *['\"]([^'\"\n]+)['\"]") do
      if func == "require" then
         addRequire(mod, name or filename)
      elseif func == "requirefile" then
         addRequireFile(mod)
      end
   end

   -- queue bundling of files identified in comments
   for func, mod in comments:gmatch(" +@(requiref?i?l?e?)[ \t]+([^ \t\n\r]+)") do
      if func == "require" then
         addRequire(mod, name or filename)
      elseif func == "requirefile" then
         addRequireFile(mod)
      end
   end
end


-- Find a module, add it to mods[], and follow its dependencies
--
function addRequire(name, from)
   vprintf("%s: require %s\n", from, name)

   if knownMods[name] then return end
   knownMods[name] = true

   -- replace `requirefile` with built-in implementation
   if name == "requirefile" then
      addMod {
         name = name,
         func = "luaopen_requirefile"
      }
      return
   end

   local filename, data = findModule(name)
   if data then
      -- found Lua source
      addSource(name, filename, data)
   elseif filename then
      -- found native extension library
      addLib(name, filename)
   else
      warn("could not find module '%s' in path\n", name)
   end
end


-- write C source file
--
local function writeCSource()
   local values = {}

   values.preloads = toC( table.concat(preloads, ";") )

   local ndx = 0
   local function emitData(o, data)
      local arrayname = "data" .. ndx
      ndx = ndx + 1

      o:fmt ("static const unsigned char %s[] = ", arrayname)

      -- Prefer string literals for readability, but avoid them if they are
      -- too long (MSVC fails "around" 64K) or if the data is binary.
      if #data >= 60000 or data:match("[\0-\7\14-\31]") then
         local bpl = 16
         o:fmt("{\n")
         for n = 1, #data, bpl do
            o:fmt("  %s\n", data:sub(n, n+bpl-1):gsub(".", function(c) return c:byte()..", " end))
         end
         -- trailing "0" avoids trailing comma (size is conveyed separately)
         o:fmt("  0\n}")
      else
         for line in data:gmatch("[^\n]*\n?") do
            o:fmt("\n  %s", toC(line))
         end
      end
      o:put ";\n\n"

      return arrayname
   end


   -- generate strings & external function declarations
   local o = Outfile:New()
   for _, m in ipairs(mods) do
      if m.data then
         m.arrayname = emitData(o, m.data)
      else
         o:fmt("extern int %s(lua_State *);\n\n", m.func)
      end
   end

   for _, r in ipairs(rfiles) do
      r.arrayname = emitData(o, r.data)
   end

   values.defs = table.concat(o)

   values.main = options.m or "main"

   -- generate mods[]
   local o = Outfile:New()
   for _, m in ipairs(mods) do
      o:fmt( "\n   { %s, %s, (const char *) %s, %d, %s }",
             toC(m.name),
             toC(m.source or m.filename and "@"..m.filename),
             m.arrayname or "0",
             m.data and #m.data or 0,
             m.func or "0" )
   end
   values.mods = table.concat(o, ",")

   -- generate rfiles[]
   if rfiles[1] then
      local o = Outfile:New()
      for _, r in ipairs(rfiles) do
         o:fmt( "\n   { %s, (const char *) %s, %s }",
                toC(r.mod),
                r.arrayname,
                #r.data )
      end
      local rfiles = table.concat(o, ",")
      values.rfilesImpl = rfilesNonEmpty:gsub("#{(%w+)}", {rfiles = rfiles})
   else
      values.rfilesImpl = rfilesEmpty
   end

   -- generate impliedLibs
   local ilibs = {}
   for _, m in ipairs(mods) do
      if m.libfile then
         table.insert(ilibs, "// lib: " .. m.libfile)
      end
   end

   values.impliedlibs = table.concat(ilibs, "\n")

   writeFile(options.o, ctemplate:gsub("#{(%w+)}", values))
end


local luaTemplate = [=[
for k, v in pairs{#{pfuncs}} do package.preload[k] = v end

#{preload}----
#{main}]=]


-- generate a Lua-based implementation of requirefile
--
local function luaRF(o)
   local template = [[
local t = {#{rfiles}}
return function (name) return t[name] end]]

   local values = {}

   local o = Outfile:New()
   for _, r in ipairs(rfiles) do
      local data = r.data
      local eqs = ""
      while data:find("]" .. eqs .. "]") do
         eqs = eqs .. "="
      end
      o:fmt("\n[%s] = [%s[%s]%s]", toC(r.mod), eqs, data, eqs)
   end
   values.rfiles = table.concat(o, ",")

   return ( template:gsub("#{(%w+)}", values) )
end


-- write a Lua source file
--
local function writeLuaSource()
   local values = {}
   local o

   -- pfuncs
   o = Outfile:New()
   for _, m in ipairs(mods) do
      local data = m.data
      if m.name == "requirefile" then
         data = luaRF()
      end
      if m.name and data then
         local k = m.name
         if not k:match("^%a[%w_]*$") then
            k = "['" .. k .. "']"
         end

         o:fmt("\n%s=function()\n%s\nend", k, data)
      end
   end
   values.pfuncs = table.concat(o, ",")

   -- require preloads
   o = Outfile:New()
   for _, mod in ipairs(preloads) do
      o:fmt("require \"%s\"\n", mod)
   end
   values.preload = table.concat(o)

   -- main
   values.main = mods[2].data

   writeFile(options.o, luaTemplate:gsub("#{(%w+)}", values))
end


local function writeDepFile(target, deps)
   local out = ""
   if deps[1] then
      out = target .. ": " .. table.concat(deps, " ") .. "\n"
      if options.MP then
         out = out .. table.concat(deps, ":\n") .. ":\n"
      end
   end

   writeFile(options.MF, out)
end


-- write make-style dependencies
--
local function writeDeps()
   local deps = {}
   for _, m in ipairs(mods) do
      local file = m.filename or options.MX and m.libfile
      if file then
         table.insert(deps, file)
      end
   end

   for _, r in ipairs(rfiles) do
      table.insert(deps, r.filename)
   end

   local lhs = options.MT or options.o
   bailIf(not lhs, "-MF requires target name; use either -o or -MT.  Try -h for help.")
   writeDepFile(lhs, deps)
end


-- Read implied dependencies from generated C file
--
local function readLibs(filename)
   local src = readFile(filename)
   bailIf(not src, "--readlibs: file not found: %s", filename)

   -- scan implied dependencies from "// lib:" lines in .c file
   local deps = {}
   for line in src:gmatch("[^\n]+") do
      local name = line:match("// lib: (.*)")
      if name then
         if options.win then
            name = name:gsub("/", "\\")
         end
         table.insert(deps, name)
      elseif not line:match("^//") then
         break
      end
   end

   -- write dependencies to stdout
   --
   -- Avoid newlines: Windows-based Lua executables use the MS C runtime
   -- which opens stdout in "ASCII mode", so carriage returns are inserted
   -- before linefeed characters. These in turn are not recognized as
   -- line separators by bash in recent versions of Cygwin when they
   -- process $( ... ) expressions.
   --
   if deps[1] then
      io.write(table.concat(deps, " "))
   end

   -- write .d (dependency file)
   if options.MF then
      bailIf(not options.MT, "--MT required with --MF and --readlibs")
      writeDepFile(options.MT, deps)
   end

   return 0
end


----------------------------------------------------------------
-- Command argument processing
----------------------------------------------------------------

local oo = "-o= -h/--help -v -w -Werror -MF= -MP -MT= -MX --path=* -s=* --deps -I=* --minify -m= -l=* -b=* --open=* --readlibs --win --luaout"

local modnames
modnames, options = getopts(arg, oo)

if os.getenv("CFROMLUA_DEBUG") then
   options.v = true
   options.w = true
end

if options.Werror then
   options.w = true
end

if options.h or options.help then
   printf2("%s", usageString)
   os.exit(0)
end

if options.readlibs then
   return readLibs(modnames[1])
end

bailIf(not (options.o or options.MF), "No output file provided.  Use -h for help.")
bailIf(not modnames[1], "No source files provided. Use -h for help.")

path = (options.path and table.concat(options.path, ";"))
   or os.getenv("CFROMLUA_PATH")
   or os.getenv("LUA_PATH")
   or package.path
   or ""

cpath =  (options.cpath and table.concat(options.cpath, ";"))
   or os.getenv("CFROMLUA_CPATH")
   or os.getenv("LUA_CPATH")
   or package.cpath
   or ""

if options.I then
   for _, dir in ipairsIf(options.I) do
      local xdir = dir:match("(.-)/?$")
      path = path .. ";" .. xdir .. "/?.lua"
      cpath = cpath .. ";" .. xdir .. "/?.lua"
   end
end

if options.v then
   for p in path:gmatch("[^;]+") do
      printf2("path: %s\n", p)
   end
   for p in cpath:gmatch("[^;]+") do
      printf2("cpath: %s\n", p)
   end
end

-- put preamble first
addMod {
   source = "(preamble)",
   data = strip2(preamble)
}

for _, name in ipairsIf(options.s) do
   knownMods[name] = true
end

-- files named as args
for _, name in ipairs(modnames) do
  local data
  if name == '-' then
     name = '<stdin>'
     data = io.stdin:read('*a')
   else
     data = readFile(name)
   end
   bailIf(not data, "could not open file: %s", name)
   addSource(nil, name, data)
end

-- preloads: add these to list of modules, incrementing mainndx
for _, name in ipairsIf(options.l) do
   addRequire(name, "-l")
   table.insert(preloads, name)
end

-- additional modules
for _, name in ipairsIf(options.b) do
   addRequire(name, "-b")
end

-- additional luaopen...() calls
for _, name in ipairsIf(options.open) do
   addLib(name)
end

if options.MF then
   writeDeps()
end

if options.o then
   if options.luaout then
      writeLuaSource()
   else
      writeCSource()
   end
end

return 0
