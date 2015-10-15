# cfromlua test (sh comment first-line)

assert(kilroyWasHere)

local requirefile = require "requirefile"

local d0 = require "dep"
local d1 = require "dep"

local m = requirefile("dep/dep.lua")
local m2 = requirefile("dep/data.txt")
local m3 = requirefile("dep/data.txt")
assert(require "debug")


print(arg[1] .. d0 .. d1 .. m:sub(1,1))
