local system = require 'system'

local function main()
  return system.directory {
    path = '.',
    contents = {
      ['build.lua'] = 'build.lua',
    },
  }
end

local function clean()
end

return {
  main = main,
  clean = clean,
}
