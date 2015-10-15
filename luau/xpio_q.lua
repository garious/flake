-- Test xpio.lua

local qt = require "qtest"
local xpio = require "xpio"

local eq = qt.eq


eq("function", type(xpio.socket))


--------------------------------
-- _searchPath
--------------------------------

eq(xpio._searchPath("as987sfd234"), nil)
eq(xpio._searchPath("sh"), "/bin/sh")


--------------------------------
-- _nextfd
--------------------------------

local fds = {}
for fd in xpio._nextfd do
   fds[#fds+1] = fd
end
assert(fds[1], 0)
assert(fds[2], 1)
assert(fds[3], 2)


--------------------------------
-- _fdjuggle
--------------------------------

local fdjuggle = xpio._fdjuggle

local function mockSocket(fd)
   return { fileno = function () return fd end }
end

-- accept numbers or objects

eq( fdjuggle({ [1]=mockSocket(2), [2]=3 }, function () end),
    { {1,2}, {2,3}, {3} } )


-- emit {fd,fd} for files that are preserved (so the file will be marked blocking)
eq( fdjuggle({ [1]=mockSocket(1) }, function () end),
    { {1,1} })


local function testJuggle(fdmap)
   local max = 9
   local function nextfd(_, fd)
      if fd == nil then
         return 0
      elseif fd < max then
         return fd + 1
      end
   end

   -- construct a simluated descriptor map
   local fds = {}
   for n = 0, max do
      fds[n] = n
   end

   local o = fdjuggle(fdmap, nextfd)

   -- execute instructions
   for _, inst in ipairs(o) do
      local to, from = inst[1], inst[2]
      if from then
         fds[to] = fds[from]
      else
         fds[to] = nil
      end
   end

   qt.eq(fds, fdmap)
end


testJuggle{ [0]=1, 2, 3, 4, 5, 6, [10]=1, [11]=7 }

testJuggle{ [1]=2, [2]=1, [3]=2, [4]=2, [5]=6, [7]=8, [8]=7, [9]=9 }

for a = 1, 4 do
   for b = 2, 3 do
      testJuggle{ [a] = b, [b] = a, [9] = a, [13] = 3 }
   end
end


--------------------------------
-- gettime & tqueue.wait(time)
--------------------------------

local sleepQueue = xpio.tqueue()
local function sleep(seconds)
   assert(sleepQueue:wait(seconds))
end


local t = xpio.gettime()
assert({nil}, {sleep(0.01)})
assert(xpio.gettime() >= t + 0.01)


-- retry a non-blocking function until it succeeds
--
local function retry(fn, ...)
   local succ, err
   for tries = 1, 50 do
      local r = table.pack( fn(...) )
      if r[1] ~= nil or r[2] ~= "retry" then
         return table.unpack(r, 1, r.n)
      end
      sleep(tries / 1000)
   end
   return nil, "xpio_q.lua:retry() timed out!"
end


--------------------------------
-- socket-related tests
--------------------------------

do
   -- socket

   eq( {xpio.socket("FOO")},
       {nil, "xpio: unsupported socket type"} )
   local a = assert(xpio.socket("TCP"))


   -- bind & getsockname

   local SERVER = "127.0.0.1:54321"
   assert(a:setsockopt("SO_REUSEADDR", true))
   eq(a:bind(SERVER), true)
   eq(a:getsockname(), SERVER)

   local c = assert(xpio.socket("TCP"))
   eq(c:bind("0:"), true)
   local name = c:getsockname()
   qt.match(name, "^0.0.0.0:%d+$")

   -- listen

   qt.eq(true, (a:listen()))

   -- try_connect

   local succ, err = retry(c.try_connect, c, SERVER)
   eq(succ, true)

   -- try_accept

   local s = assert(retry(a.try_accept, a))

   -- getsockopt / setsockopt

   eq(false, s:getsockopt("TCP_NODELAY"))
   eq(true, s:setsockopt("TCP_NODELAY", true))
   eq(true, s:getsockopt("TCP_NODELAY"))

   eq(true, s:getsockopt("O_NONBLOCK"))
   eq(true, s:setsockopt("O_NONBLOCK", false))
   eq(false, s:getsockopt("O_NONBLOCK"))
   eq(true, s:setsockopt("O_NONBLOCK", true))
   eq(true, s:getsockopt("O_NONBLOCK"))

   -- getpeername

   qt.match(c:getpeername(), "^127.0.0.1:54321")

   -- read cases:  data, retry, end, error

   -- read retry
   eq( {s:try_read(100)},
       {nil, "retry"} )

   -- read data ( making some assumptions about chunking here)
   local MSG1 = "This is a test"
   eq(c:try_write(MSG1), #MSG1)
   eq(retry(s.try_read, s, 100), MSG1)

   -- read end
   assert(c:shutdown("wr"))
   eq(nil, retry(s.try_read, s, 100))

   -- read error
   -- todo

   -- close

   eq(s:close(), true)
   eq(c:close(), true)


   -- when_read, when_write, and tqueues

   c = xpio.socket("TCP")
   eq( retry(c.try_connect, c, SERVER), true)
   s = assert( retry(a.try_accept, a) )

   local queue = xpio.tqueue()

   -- nothing to wait on
   eq(queue:wait(), nil)
   eq(queue:wait(false), nil)

   c:when_write{ _queue = queue, name = "c w"}
   c:when_read{ _queue = queue, name = "c r"}
   s:when_read{ _queue = queue, name = "s r"}

   -- client should be writable
   local r, time = queue:wait(10)
   eq(#r, 1)
   eq(r[1].name, "c w")
   eq(r[1]._dequeue, nil)

   c:try_write("X")
   -- server should be readable; "c w" should have been de-queued
   r, time = queue:wait(10)
   eq(#r, 1)
   eq(r[1].name, "s r")

   eq(s:try_read(2), "X")

   c:close()
   s:close()
   a:close()
end


-- pipes

local function pipeTest()
   local r, w = xpio.pipe()

   local amt = w:try_write("Hello")
   local data = r:try_read(1000)
   eq(amt, 5)
   eq(data, "Hello")
   r:close()
   w:close()

   -- child processes
   local r0, w0 = xpio.pipe()
   local r1, w1 = xpio.pipe()

   local proc = xpio.spawn({"echo", "foo"},
                           {A="X", B="YZ"},
                           {[0]=r0, [1]=w1, [2]=w1},
                           {})

   local tq = xpio.tqueue()
   proc:when_wait{ _queue = tq, name = "ls proc"}

   local r, time = tq:wait(2)
   eq(#r, 1)
   eq(r[1].name, "ls proc")
   eq({proc:try_wait()}, {"exit", 0})

   r1:close()
   w0:close()
end
pipeTest()


----------------------------------------------------------------
-- Minimal dispatcher
----------------------------------------------------------------

-- This exercises xpio.setCurrentTask and allows blocking functions to be
-- tested, and by enabling blocking functions, it makes it easier to test
-- socket and sub-process operations.

local function dispatch(threadFunc)
   local complete = false
   local tq = xpio.tqueue()

   local task = {}
   task._queue = tq
   task.thread = coroutine.create(function () threadFunc(); complete = true end)
   function task:run()
      local succ, err = coroutine.resume(self.thread)
      if not succ then
         error("Failure in coroutine: \n" .. err)
      end
   end

   local ready = { task }
   while ready do
      for _, t in ipairs(ready) do
         xpio.setCurrentTask(t)
         t:run()
      end
      ready = tq:wait()
   end
   xpio.setCurrentTask(nil)
   assert(complete)
end


----------------------------------------------------------------
-- synchronous xpio.spawn() tests
----------------------------------------------------------------


local function testWait()
   local r0, w0 = xpio.pipe()   -- stdin
   local r1, w1 = xpio.pipe()   -- stdout/stderr

   local proc = xpio.spawn({"not_echo", "2"}, {},
                           {[0]=r0, [1]=w1, [2]=w1},
                           {exe = "echo"})
   local a, b = proc:wait()
   eq(a, "exit")
   eq(b, 0)
   r1:close()
   w0:close()
end
dispatch(testWait)


-- redirect

local function testProcs()
   local r0, w0 = xpio.pipe()
   local r1, w1 = xpio.pipe()

   local proc = xpio.spawn({"grep", "bar"},
                           {A="X", B="YZ"},
                           {[0]=r0, [1]=w1, [2]=w1},
                           {})

   assert(w0:write("foo\nbar\nbaz\n"))
   w0:close()

   assert(proc:wait())

   local out = ""
   while true do
      local d = r1:read(100)
      if not d then break end
      out = out .. d
   end
   eq(out, "bar\n")
   r1:close()
end
dispatch(testProcs)


local function testFDOpen()
   local f = xpio.fdopen(1)
   f:write("write via fdopen succeeded") -- TODO: automate this test
end

dispatch(testFDOpen)
