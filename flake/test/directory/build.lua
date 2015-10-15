local system = require 'system'

local function main()
  return system.directory {
    path = 'out',
    contents = {
      ['build.lua'] = 'build.lua',
    },
  }
end

local function clean()
  return system.removeDirectory 'out'
end

return {
  main = main,
  clean = clean,
}
