local qt = require "qtest"
local list = require "list"
local xe, _xe = qt.load("xpexec.lua", {"visitAndAppend"})

local luacmd = assert(os.getenv("LUA"))
local luaflagstr = os.getenv("LUA_FLAGS") or ''
local luaflags = {}
for word in luaflagstr:gmatch("[^ ]+") do
    table.insert(luaflags, word)
end
local v = os.getenv("xpexec_q_v")

local function pquote(str)
   return (str:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"):gsub("%z", "%%z"))
end

----------------------------------------------------------------
-- Tests
----------------------------------------------------------------


-- ** visitAndAppend()

local t = {}
_xe.visitAndAppend(t, {1,{},{2,3},{4,{5}},{{6}}, {raw=true, 7}}, function (n) return n+n end)
qt.eq( {2,4,6,8,10,12,7}, t )


local t = {}
_xe.visitAndAppend(t, {{1},2}, function (n, first) return first end)
qt.eq( {true,false}, t )


-- ** quoteArgWin()

qt.eq('"a b"', xe.quoteArgWin('a b'))
qt.eq('^"',    xe.quoteArgWin('"'))
qt.eq('a/b',   xe.quoteArgWin('a/b'))
qt.eq('"a/b"', xe.quoteArgWin('a/b', true))

-- ** quoteArgNix()

qt.eq("'a b'", xe.quoteArgNix("a b"))
qt.eq("'&'",   xe.quoteArgNix('&'))


-- ** quoteCommand() flattens arguments

qt.eq("a b c d >x",  xe.quoteCommand("a", {"b", {}, {{"c"}}}, "d", {raw=true, ">x"}) )

-- ** quoteCommand() handles weird Win32 whole-command quoting

if xe.isWindows() then
   qt.eq('""a/b c" d"', xe.quoteCommand("a/b c", "d"))
else
   qt.eq("'a/b c' d", xe.quoteCommand("a/b c", "d"))
end

-- ** isWindows() should return boolean (nil => OS detection failed)

qt.eq("boolean", type(xe.isWindows()))

-- ** quoteArg

local f = xe.isWindows() and xe.quoteArgWin or xe.quoteArgNix
qt.eq(f("$"),  xe.quoteArg("$"))

-- ** quoteCommand() quotes special characters for the current platform when
--    invoking an executable

local function echoTest(str)
   local args = list.append(luaflags, {"-e", 'print(([['..str..']]):gsub(" ","_"))'})
   local cmd = xe.quoteCommand(luacmd, table.unpack(args))
   if v then print("Command: " .. cmd) end
   local p = io.popen(cmd, "r")
   local out = p:read("*a")
   p:close()
   return qt.match(out, pquote(str:gsub(" ","_")))
end

echoTest  "! \" # $ % & ' ( ) * + , - . : ; < = > ? @ [ \\ ] ^ _ ` { | } ~"

echoTest "( [ { <"

echoTest '"'

echoTest "%path%"



-- ** Windows interprets "/" in executable path as switch unless it's quoted.

luacmd = luacmd:gsub("\\", "/")


-- ** Windows CMD has special rule for commands beginning with '"'

echoTest 'a "b"'

