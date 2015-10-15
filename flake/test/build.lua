local flake    = require 'flake'
local ops      = require 'operatorBuilders'
local list     = require 'list'

local testDirs = list:new {
  'directory',
  'copyToSelf',
}

local builds = testDirs:map(flake.importBuild)

local function main(ps)
  return builds:map(function(bld) return bld.main(ps) end)
end

local function clean(ps)
  return builds:map(function(bld) return bld.clean(ps) end)
end

return {
  main = main,
  clean = clean,
}
