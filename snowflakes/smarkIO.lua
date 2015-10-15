local systemIO = require 'systemIO'
local path     = require 'path'
local lfsu     = require 'lfsu'

-- Given a text file, generate a smark HTML file
local function html(cfg, ps)
  local sourceFile
  if type(ps) == 'string' then
    sourceFile = ps
  elseif type(ps) == 'table' and type(ps[1]) == 'string' then
    sourceFile = ps[1]
  else
    sourceFile = ps.sourceFile
  end
  local outName = path.takeBaseName(sourceFile) .. '.html'
  local outPath = cfg.outPath or cfg.buildDir .. '/' .. outName
  local outDir = path.takeDirectory(outPath)
  local args = {ps.smark, '-o', outPath, sourceFile}
  local env = {}
  if type(ps.includeDirs) == 'table' and #ps.includeDirs > 0 then
    env.SMARK_PATH = table.concat(ps.includeDirs, '/?.lua;') .. '/?.lua'
  end
  lfsu.mkdir_p(outDir)
  return systemIO.execute(cfg, {args=args, env=env, thenReturn=outPath})
end

return {
  html = html,
}
