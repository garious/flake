local getopts = require 'getopts'

local function parseArg(t, ar)
  local k, v = ar:match('([^=]+)=(.+)')
  if k then
    local old = t[k]
    if type(old) == 'table' then
      table.insert(t[k], v)
    elseif old == nil then
      t[k] = v
    else
      t[k] = {old, v}
    end
  else
    table.insert(t, ar)
  end
end

local usage = [=[
Usage: flake [OPTIONS]... [FILE [TARGET [TARGET_PARAMS]]]
Options:
--directory=DIR   -C DIR  Change to this directory first
--penniless               Run as fast as possible.  No cache.
--quiet                   Don't output commands.
--silent          -s      Output as little as possible.
--version         -v      Print flake version and exit
--package=DIR     -I DIR  Include package directory
                  -e STR  Execute statement
]=]

local function parseArgs(args, errHdlr)
  local opts = {
    '--directory/-C=',  -- Change to this directory first
    '--penniless',      -- Run as fast as possible.  No cache.
    '--quiet',          -- Don't output commands.
    '--silent/-s',      -- Output as little as possible.
    '--version/-v',     -- Print flake version and exit
    '--package/-I=*',   -- Include package directory
    '-e=',              -- Execute statement
    '-',                -- Execute stdin
  }

  local args, options = getopts.read(args, opts, errHdlr)

  options.directory = options.directory or '.'
  options.file = args[1] or 'build.lua'

  local targetArgs = {}
  for i,ar in ipairs(args) do
    if options.e or i > 1 then  -- not options.e => args[1] == options.file
      parseArg(targetArgs, ar)
    end
  end
  return options, targetArgs
end

return {
  parseArg = parseArg,
  parseArgs = parseArgs,
  usage = usage,
}

