local qt = require "qtest"
local xc = require "xpio_c"
local cmap = require "cmap"

local eq = qt.eq


--------------------------------
-- inspect `xpio` contents
--------------------------------

local contents = {
   socket = "function",
   tqueue = "function",
   gettime = "function",
   socketpair = "function",
   fdopen = "function",
   pipe = "function",
   env = "table",
   _spawn = "function",
   _nextfd = "function",
   _XPSocket = "table",
   _XPQueue = "table",
   _XPProc = "table"
}

eq(contents, cmap.x("k,type(v)")(xc))

eq("function", type(xc._XPSocket.bind))
eq("function", type(xc._XPQueue.wait))
eq("function", type(xc._XPProc.kill))


--------------------------------
-- env
--------------------------------

eq(xc.env.PATH, os.getenv("PATH"))


--------------------------------
-- gettime
--------------------------------

eq("number", type(xc.gettime()))


--------------------------------
-- tqueue
--------------------------------

local tq = xc.tqueue()
eq("userdata", type(tq))
qt.same(xc._XPQueue,  getmetatable(tq))

eq(true, tq:isEmpty())

-- Make a function that waits on a single operation.
--
local function block(tryName, whenName)
   local tryMethod = "try_" .. tryName
   local whenMethod = "when_" .. (whenName or tryName)

   return function(obj, ...)
      for n = 1, 3 do

         -- try: see if it's complete
         local results = table.pack(obj[tryMethod](obj, ...))
         if results[1] ~= nil or results[2] ~= "retry" then
            return table.unpack(results)
         end

         -- when: add event to queue
         obj[whenMethod](obj, { _queue = tq })

         eq(false, tq:isEmpty())

         -- wait: wait for event
         tq:wait(0.1)
      end
      assert("should not get here!")
   end
end


--------------------------------
-- pipe
--------------------------------

local read = block("read")

local r1, w1 = xc.pipe()
eq({8}, {w1:try_write("hi there")})
eq({"hi there"}, { read(r1, 99) })
eq({true}, {r1:close()})
eq({true}, {w1:close()})


--------------------------------
-- proc
--------------------------------

local rp, wp = xc.pipe()

local proc = xc._spawn("/bin/echo", {"echo", "foo"}, {}, { {1, wp:fileno()} })

eq("userdata", type(proc))
qt.same(xc._XPProc, getmetatable(proc))
eq({"foo"}, { read(rp, 3) })
eq({"exit", 0}, {block("wait")(proc)})


--------------------------------
-- socket
--------------------------------

local sock = xc.socket("TCP")
eq("userdata", type(sock))
qt.same(xc._XPSocket,  getmetatable(sock))

-- socket:accept() should also create a usable socket

eq({true}, {sock:bind("127.0.0.1:")})
eq({true}, {sock:listen()})

local sock2 = xc.socket("TCP")

local connected = block("connect", "write")(sock2, sock:getsockname())
eq(connected, true)

local sock3 = block("accept", "read")(sock)
eq("userdata", type(sock3))
qt.same(xc._XPSocket,  getmetatable(sock))

eq(true, sock3:close())
eq(true, sock2:close())
eq(true, sock:close())
