-- An example of creating processes
--

local qt = require "qtest"
local thread = require "thread"
local xpio = require "xpio"


-- Read all data from `s`, appending to table `output`
--
local function readFrom(s, output)
   repeat
      local data, err = s:read(4096)
      if data then
         table.insert(output, data)
      else
         s:close()
         return
      end
   until false
end


-- Write all of `input` to `s`.  `input` is a string.
--
local function writeTo(s, input)
   while input and input ~= "" do
      local num, err = s:write(input)
      if num then
         input = input:sub(num+1)
      else
         break
      end
   end
   s:close()
end


local function runCommand(str, input, output)
   local args = {}
   for w in str:gmatch("[^ \t]+") do
      table.insert(args, w)
   end

   local r0, w0 = xpio.pipe()   -- stdin
   local r1, w1 = xpio.pipe()   -- stdout/stderr

   local proc = xpio.spawn(args, {}, {[0]=r0, [1]=w1, [2]=w1})

   thread.new(writeTo, w0, input)
   thread.new(readFrom, r1, output)

   return proc
end


local function main()
   local commands = {
      { str="make help" },
      { str="ls" },
      { str="grep bar", input="foo\nbar\nbaz\n" }
   }

   -- start processes
   for _, c in ipairs(commands) do
      c.outs = {}
      c.proc = runCommand(c.str, c.input, c.outs)
   end

   -- wait for exit and show results
   for _, c in ipairs(commands) do
      local reason, code = c.proc:wait()
      print(string.format("%s --> %s (%s)", c.str, reason, code))
      print(table.concat(c.outs))
   end
end

thread.dispatch(main)
