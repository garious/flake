-- Flake builders for C programs

local flake   = require 'flake'
local c       = flake.requireBuilders 'cIO'
local list    = require 'list'
local system  = require 'system'
local listBuilders = require 'listBuilders'

-- Extend the library builder to accept source files instead of
-- only object files.
local library = c.library
c.library = function(ps)
  local ps = list.clone(ps)
  if ps.ar == nil then
    ps.ar = c.config.ar
  end
  if type(ps.sourceFiles) == 'table' then
    local function mkObj(src)
      local ps = list.clone(ps)
      ps.sourceFiles = nil
      ps.objectFiles = nil
      ps.sourceFile = src
      return c.object(ps)
    end
    local objs = listBuilders.map(ps.sourceFiles, mkObj)
    if type(ps.objectFiles) == 'table' then
      listBuilders.append(ps.objectFiles, objs)
    else
      ps.objectFiles = objs
    end
  end
  ps.sourceFiles = nil
  return library(ps)
end

c.run = function(ps)
  local args = {c.program(ps)}
  for _,v in ipairs(ps.args or {}) do
    table.insert(args, v)
  end
  return system.execute(args)
end

c.configure = function(ps)
  for k,v in pairs(ps) do
    c.config[k] = v
  end
end

c.getCC = function()
  return c.config.cc
end

c.getCXX = function()
  return c.config.cxx
end

c.getAR = function()
  return c.config.ar
end

return c

