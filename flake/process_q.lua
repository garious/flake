local process = require 'process'
local qtest   = require 'qtest'
local thread  = require 'thread'

local function main()
  qtest.eq(table.pack(process.readProcess{'echo', 'abc'}), {nil, 'abc', '', 'exit', n=4})
end

thread.dispatch(main)

