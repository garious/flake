-- Flake builders for the operating system

local flake = require 'flake'

local system = flake.requireBuilders 'systemIO'

--
-- Optimize away unnecessary file copies
--
-- Note: This modifies 'builder' objects
local function optimizeCopies(x, tgt)
  if flake.isBuilder(x) then
    x._priv.outPath = tgt
  elseif type(x) == 'table' then
    for k,v in pairs(x) do
      optimizeCopies(v, type(tgt) == 'string' and tgt .. '/' .. k)
    end
  end
end

local directory = system.directory
system.directory = function(ps)
  optimizeCopies(ps.contents, ps.path)
  return directory(ps)
end

return system

