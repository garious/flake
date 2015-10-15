local qt = require "qtest"
-- @require fsu
--local fsu, xrelpathto = qt.magicload "fsu.lua"
local fsu, _fsu = qt.load("fsu.lua", {"xrelpathto"})


local nix, win = fsu.nix, fsu.win

local T = qt.tests


function T.nix_cleanpath()
   local function tcp(a,b)
      qt._eq(nix.cleanpath(a), b, 2)
   end

   tcp("a/.", "a")
   tcp("/a/.", "/a")
   tcp("a/..", ".")
   tcp("/a/..", "/")
   tcp("a/b/../..", ".")
   tcp("/a/b/../..", "/")
   tcp("a/../..", "..")
   tcp("/a/../..", "/..")

   tcp("./b", "b")
   tcp("/./b", "/b")
   tcp("a/./b", "a/b")
   tcp("/a/./b", "/a/b")

   tcp("a/./././././././b", "a/b")
   tcp("a./b", "a./b")
   tcp("a/.b", "a/.b")

   tcp("a/..", ".")
   tcp("a/b/..", "a")
   tcp("../b", "../b")
   tcp("a/../b", "b")
   tcp("/a/../b", "/b")
   tcp("b/..a", "b/..a")
   tcp("b../a", "b../a")
   tcp("b../..a", "b../..a")
   tcp("b../..a", "b../..a")

   tcp("/..", "/..")
   tcp("a/b/c/d/../../..", "a")
   tcp("a/b/c/d/../../e", "a/b/e")

   tcp("/a/./../b", "/b")
   tcp("./../b", "../b")
   tcp("/a/b/./.././c", "/a/c")

   tcp("a/.././.", ".")
   tcp("a/.../b", "a/.../b")

   tcp("../../a", "../../a")
   tcp("../../../a", "../../../a")
   tcp("a/../../b", "../b")

   tcp("c:/..", ".")
end


function T.win_cleanpath()
   local function tcp(a,b)
      qt._eq(win.cleanpath(a), b, 2)
   end

   tcp("c:/..", "c:/..")
end


function T.nix_splitpath(p)
   local function t(path, dir, file)
      qt._eq( {nix.splitpath(path)}, {dir,file}, 2 )
   end

   t("c:\\a",       ".",         "c:\\a")   -- not Windows
   t("c:/a",        "c:",        "a")       -- not Windows

   t("/a",          "/",         "a")
   t("/a/",         "/",         "a")
   t("/...",        "/",         "...")

   t("/",           "/",         ".")
end


function T.win_splitpath(p)
   local function t(path, dir, file)
      qt._eq( {win.splitpath(path)}, {dir,file}, 2 )
   end

   t("c:/d/e/f",    "c:/d/e",   "f")
   t("C:\\x\\y\\z", "C:/x/y",   "z" )
   t("c:\\a",       "c:/",      "a")
   t("\\a\\b",      "/a",       "b")
   t("/a/b",        "/a",       "b")

   t("c:/",         "c:/",      ".")
end


local function tr(os, a, b, result)
   qt._eq(os.resolve(a,b), result, 2)
end


function T.nix_resolve()
   tr(nix, "/a", "/a/b",   "/a/b")
   tr(nix, "/a", "c:/b",   "/a/c:/b")
   tr(nix, "c:/a", "/b",   "/b")
   tr(nix, "c:\\a", "/b",   "/b")
end


function T.win_resolve()
   tr(win, "c:/A", "b",     "c:/A/b")
   tr(win, "x:/a", "/b",    "x:/b")
   tr(win, "c:/a", "d:/b",  "d:/b")
   tr(win, "c:/a/../c", "x",  "c:/c/x")
   tr(win, "/a",  "/b/../c", "/c")

   tr(win, "/a/b",  "c\\d", "/a/b/c/d")
   tr(win, "/",     "/c\\d", "/c/d")
end


function T.xrelpath()
   local function streq(a,b) return a==b end
   local function tt(src, dst, result)
      qt._eq(result, _fsu.xrelpathto(src, dst, streq), 2)
      qt._eq(result, _fsu.xrelpathto(src.."/", dst, streq), 2)
   end

   tt( "/a/b",    "/a/b/c",    "c" )
   tt( "/a/b",    "/a/b/c/d",  "c/d" )
   tt( "/a/b",    "/a/b",      "." )
   tt( "/a/b/c",  "/a/b",      ".." )
   tt( "/a/b/c",  "/a/",       "../.." )
   tt( "/a/b",    "/",         "../.." )
end


function T.nix_relpathto()
   local cwd = "/x/y/z"
   local function tt(src, dst, result)
      qt._eq(result, nix.relpathto(src, dst, cwd), 2)
      qt._eq(result, nix.relpathto(src.."/", dst, cwd), 2)
   end

   -- abs abs (finer-grained cases covered above in xrelpath)
   tt( "/a/b",    "/a/b/c",    "c" )

   -- rel rel
   tt("a/b",     "../c",   "../../../c")
   tt("../b",     "../c",   "../c")
   tt("b",        "../c",   "../../c")

   -- rel abs
   tt("b",        "/r",     "../../../../r")

   -- abs rel
   tt("/b",        "c",     "../x/y/z/c")


   -- no CWD
   cwd = nil

   tt("a/b/c",    "a/b/d",    "../d")
   tt("../b/c",   "../b/d",   "../d")
   tt("/../..",   "/../../d",  "d")

   tt("a",        "/a",       "/a")

   tt("../..",    "x",        nil)
   tt("/../..",   "/../d",    nil)
   tt("/a/b",     "x",        nil)
end


function T.win_relpathto()
   local cwd = "c:/x/y/z"

   local function tt(src, dst, result)
      qt._eq(result, win.relpathto(src, dst, cwd), 2)
      qt._eq(result, win.relpathto(src.."/", dst, cwd), 2)
   end

   -- dev dev
   tt("C:/a",   "C:/a/b",  "b")
   tt("c:/x/y/z/x",  "C:/b",  "../../../../b")

   -- dev  nodev
   tt("a:/a",   "/b",     "c:/b")
   tt("C:/a",   "/b",     "../b")
   tt("a:/a",   "../b",   "c:/x/y/b")

   --  nodev dev
   tt("x",      "C:/b",   "../../../../b")
   tt("../b",   "a:/b",   "a:/b")


   -- nodev nodev
   tt("a/b",     "../c",   "../../../c")
end


return qt.runTests()

