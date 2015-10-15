local qt = require "qtest"
local xpfs = require "xpfs"
local lfsu = require "lfsu"

local T = qt.tests

----------------------------------------------------------------

local function norm(name)
   return name:gsub("\\", "/"):gsub("/?$", "")
end

local cwd = norm( xpfs.getcwd() )

local tmpdir = norm( assert(os.getenv("OUTDIR")) ) .. "/lfsu_q_tmp"

local function tmp(f)
   return tmpdir .. "/" .. f
end

----------------------------------------------------------------

function T.abspath()
   qt.eq( cwd.."/a",  lfsu.abspath("a") )
end

function T.relpathto()
   qt.eq("z/b",  lfsu.relpathto("..", "b", "/x/y/z") )
   qt.eq(cwd:match("[^/]*$").."/b",  lfsu.relpathto("..", "b") )
end


local function isDir(name)
   local x = xpfs.stat(name, "k")
   return x and "d" == x.kind
end

-- rm_rf() and mkdir_p() tests also provide coverage for read() and write()

function T.rm_rf()
   xpfs.mkdir( tmpdir )
   assert( isDir(tmpdir), tmpdir )

   for _,name in ipairs { "d", "d/e", "d/e/f" } do
      assert( xpfs.mkdir( tmp(name) ) )
   end
   for _,name in ipairs { "a", "d/e/c", "d/e/f/ro" } do
      lfsu.write( tmp(name), "text")
   end
   assert( xpfs.chmod( tmp("d/e/f/ro"), "-w") )

   assert( lfsu.rm_rf( tmpdir ) )

   qt.eq(nil, (xpfs.stat(tmpdir)) )
end


function T.mkdir_p()
   xpfs.mkdir( tmpdir )
   assert( isDir(tmpdir) )

   lfsu.write( tmp("foo"), "footext")

   local e,m = lfsu.mkdir_p( tmp("a/b") )
   assert(e)
   assert(isDir(tmp("a/b")))

   local e,m = lfsu.mkdir_p( tmp("foo/a") )
   assert(not e)
   qt.match(m, "could not create")
   qt.eq("footext", lfsu.read( tmp("foo"), "footext"))

   lfsu.rm_rf( tmpdir )
end


return qt.runTests()
