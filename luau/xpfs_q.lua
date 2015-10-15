local qt = require "qtest"
local xpfs = require "xpfs"

qt.eq("function", type(xpfs.stat))
qt.eq("function", type(xpfs.chmod))
qt.eq("function", type(xpfs.remove))

----------------
-- stat
----------------

local statFile = "xpfs_q.lua"

local r, err = xpfs.stat("DOESNOTEXIST", "p")
qt.eq(nil, r)
qt.match(err, "No such")

local fields = {
   {"time", "number"},
   {"atime", "number"},
   {"mtime", "number"},
   {"ctime", "number"},
   {"dev", "number"},
   {"gid", "number"},
   {"uid", "number"},
   {"inode", "number"},
   {"size", "number"},
   {"perm", "string", "^r[-w][-x][-r][-w]%-[-r][-w]%-$"},
   {"kind", "string", "^f$"},
}

local rAll = xpfs.stat(statFile, "*")

for _, f in ipairs(fields) do
   local field, ty, pat = table.unpack(f)

   local r, err = xpfs.stat(statFile, field:sub(1,1))
   qt.eq(nil, err)
   qt.eq(ty, type(r[field]))
   if pat then
      qt.match(r[field], pat)
   end

   -- "*" should return every field
   qt.eq(r[field], rAll[field])
end

qt.eq(true, rAll.time >= rAll.ctime)
qt.eq(true, rAll.time >= rAll.mtime)

-- stat(name, "*") == stat(name)
qt.eq(rAll, xpfs.stat(statFile))


----------------
-- chmod
----------------

-- Note: chmod affects only the user bits

local tmpdir = assert(os.getenv("OUTDIR"))
local fname = tmpdir .. "/xpfs_q_file"

local f = io.open(fname, "w")
f:write("hello")
f:close()

qt.eq("rw-", xpfs.stat(fname, "p").perm:sub(1,3))

-- subtract
xpfs.chmod(fname, "-w")
qt.eq("r--", xpfs.stat(fname, "p").perm:sub(1,3))

-- add
xpfs.chmod(fname, "+wr")
qt.eq("rw-", xpfs.stat(fname, "p").perm:sub(1,3))

-- set
xpfs.chmod(fname, "r");
qt.eq("r--", xpfs.stat(fname, "p").perm:sub(1,3))


----------------
-- remove
----------------

xpfs.remove(fname)
qt.eq(nil, (xpfs.stat(fname, "p")))


----------------
-- mkdir
----------------

local newdir = tmpdir .. "/newdir"

qt.eq( nil, (xpfs.stat(newdir, "k")) )
qt.eq( {true}, {xpfs.mkdir(newdir)} )
qt.eq( {kind="d"}, (xpfs.stat(newdir, "k")) )

----------------
-- getcwd
----------------

local cwd = xpfs.getcwd()
qt.eq("string", type(cwd))

----------------
-- chdir
----------------

-- CWD to newdir and back
qt.eq( {true}, {xpfs.chdir(newdir)} )
qt.eq(nil, (xpfs.stat(statFile, "k")))

qt.eq({true}, {xpfs.chdir(cwd)} )
qt.eq({kind="f"}, (xpfs.stat(statFile, "k")))

----------------
-- rmdir
----------------

-- remove newdir
qt.eq({true}, {xpfs.rmdir(newdir)})
qt.eq( nil, (xpfs.stat(newdir, "k")) )


----------------
-- rename
----------------

-- create new file and rename it

local mvfrom = tmpdir .. "/xpfs_a"
local mvto = tmpdir .. "/xpfs_b"

local f = io.open(mvfrom, "w")
f:write("abc")
f:close()

qt.eq(3, xpfs.stat(mvfrom, "s").size)
qt.eq({true}, {xpfs.rename(mvfrom, mvto)})
qt.eq(nil, (xpfs.stat(mvfrom, "s")) )
qt.eq(3, xpfs.stat(mvto, "s").size)

xpfs.remove(mvto)

----------------
-- rename
----------------

local r, err = xpfs.dir(".")
qt.eq(nil, err)

local rmap = {}
for _, f in ipairs(r) do
   rmap[f] = true
end
qt.eq(true, rmap[".."])
qt.eq(true, rmap["."])
qt.eq(true, rmap["xpfs_q.lua"])

