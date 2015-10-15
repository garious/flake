--
-- This file is imported by Flake builds and used
-- to describe the different build variants available.
--

return {
  flavor = {'release', 'debug', default = 'release', type = 'string'},
  outdir = {default = 'out/release', type = 'string'},
}

