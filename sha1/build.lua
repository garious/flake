package '../snowflakes'

local system   = require 'system'
local c        = require 'c'
local lua      = require 'lua'
local params   = require 'commonParams'

local function main(ps)
  return system.directory {
    path = ps.outdir,
    contents = {
      ['libsha1.lib'] = c.library {
        sourceFiles = {'sha1.c', 'sha1_lua.c'},
        includeDirs = {lua.tools().path .. "/inc"},
        flavor = ps.flavor,
      },
    },
  }
end

local function clean(ps)
  return system.removeDirectory(ps.outdir)
end

return {
  main = main,
  clean = clean,
  params = params,
}

