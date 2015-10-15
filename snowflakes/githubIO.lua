local systemIO = require 'systemIO'
local process  = require 'process'

local sh = systemIO.execute

local function addFile(cfg, p)
  if type(p) == 'string' then
    sh(cfg, {'git', 'add', p})
  elseif type(p) == 'table' then
    for _,v in pairs(p) do
      addFile(cfg, v)
    end
  end
  return nil
end

local function currentBranch()
  local err, s = process.readProcess{'git', 'rev-parse', '--abbrev-ref', 'HEAD'}
  assert(not err, err)
  return s
end

-- push files to gh-pages
local function publishHtml(cfg, ps)
  local err
  local origBranch = currentBranch()

  err = sh(cfg, {'git', 'checkout', 'gh-pages'})
  if err ~= nil then
    -- Create a new branch with no commit history
    err = sh(cfg, {'git', 'checkout', '--orphan', 'gh-pages'})
  end

  if err ~= nil then
    error(err)
  end

  -- Delete all tracked files
  if err == nil then
    err = sh(cfg, {'git', 'rm', '-rf', '.'})
  end

  -- Copy in HTML
  local err, dir = systemIO.directory(cfg, {
    path = ps.path,
    contents = ps.contents,
  })
  if err ~= nil then
    error(err)
  end

  err = addFile(cfg, dir.contents)

  -- Verify all files are in the git cache
  err = sh(cfg, {'git', 'diff', '--exit-code'})
  if err ~= nil then
    error('githubIO.publishHtml: internal error: untracked changes detected')
  end

  -- double-check
  err = sh(cfg, {'sleep', '1'})
  err = sh(cfg, {'git', 'diff', '--exit-code'})

  if err ~= nil then
    error('githubIO.publishHtml: internal error: untracked changes detected')
  end

  err = sh(cfg, {'git', 'diff', '--cached', '--exit-code'})
  if err ~= nil then
    err = sh(cfg, {
      args = {'git', 'commit', '-m', 'Updated HTML'},
      env = {
        HOME   = os.getenv 'HOME', -- Allow git to find ~/.gitconfig
      },
    })
    if err ~= nil then
      cfg.io[2]:write('publishIO.html: failed to commit, bailing out.\n')
      sh(cfg, {'git', 'reset', '--hard'})
    end
  end

  -- Return to original branch
  sh(cfg, {'git', 'checkout', origBranch})

  return err
end

return {
  publishHtml = publishHtml,
}
