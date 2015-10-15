local qt = require "qtest"
local thread = require "thread"
local xpio = require "xpio"

local o = {}
local function log(x)
   table.insert(o, x)
end

-- Dispatch a function and expect log contents
--
local function run(out, fn, ...)
   o = {}
   thread.dispatch(fn, ...)
   return qt.eq(o, out)
end


-- >> Dispatch one function and terminate.
-- >> Ensure arguments are properly passed.

local function logArgs(...)
   for n = 1, select('#', ...) do
      log( select(n, ...) or "nil" )
   end
end

run( {101,"nil"}, logArgs, 101, nil)


-- >> Create and run a second thread.

local function tf2(...)
   local t = thread.new(logArgs, ...)
end

run( {201,2,3}, tf2, 201, 2, 3)


-- >> Yield from one thread to another

local function logArgsY(...)
   for n = 1, select('#', ...) do
      log( select(n, ...) or "nil" )
      thread.yield()
   end
   return ...
end

local function tf3(cnt)
   thread.new(logArgsY, 1, 2)
   thread.new(logArgsY, 11, 12)
end

run( {1,11,2,12}, tf3, 2)


-- >> Nested invocations of dispatch() must complete synchronously and must
--    not disturb outer invocations of dispatch().

o = {}
local function tnest()
   thread.new(logArgsY, 1, 2)
   thread.dispatch(logArgsY, 11, 12)
end

run({11,12,1,2}, tnest)


-- >> join() waits for completion of another thread (when thread's start
--    function returns).
-- >> join() returns the return values of the thread.

local function tj1()
   local t = thread.new(logArgsY, 1, 2, nil)
   local o = table.pack(thread.join(t))
   log(o)
end

run( {1,2,"nil",{n=3,1,2}}, tj1 )


-- >> join() returns immediately if the thread has already completed.

local function tj2()
   local t = thread.new(logArgs, 1)
   log(11)
   thread.yield()
   thread.yield()
   thread.join(t)
   log(12)
end

run( {11,1,12}, tj2 )


-- >> atExit functions are called in reverse order.
-- >> atExit functions are passed arguments properly.
-- >> cancelAtExit prevents an atExit from being called.

local function ae1()
   local id1 = thread.atExit(logArgs, 1, nil)
   local id2 = thread.atExit(logArgs, 2)
   local id3 = thread.atExit(logArgs, 3)

   thread.cancelAtExit(id2)
end

run( {3, 1, "nil"}, ae1 )


-- >> Killing a task prevents further callbacks.
--     a) When it's in the ready queue.
--     b) When it'swaiting on join()

-- >> kill() triggers atExit() callbacks.

-- >> Killing a task will awaken other tasks that are waiting on it
--    with join().

local function tk1()
   local t1 = thread.new(function ()
                            thread.atExit(log, 19)
                            log(11)
                            thread.yield()
                            log(12)
                         end)

   local t2 = thread.new(function ()
                            thread.atExit(log, 29)
                            log(21)
                            thread.join(t1)
                            log(22)
                         end)

   local t3 = thread.new(function ()
                            thread.join(t2)
                            log(31)
                         end)

   thread.yield()
   log(1)
   thread.kill(t2)  -- waiting on join
   thread.kill(t1)  -- in ready queue
end

run( {11, 21, 1, 29, 19, 31}, tk1 )


-- >> Sleep & sleepUntil put a thread to sleep.

local function ts1()
   thread.new(function () thread.sleep(0.05) ; log(5) end)
   thread.new(function () thread.sleep(0.01) ; log(1) end)
   thread.sleepUntil(xpio.gettime() + 0.03)
   log(3)
end

-- >> Catch an exception thrown from the top-level task.

local function ce1()
   -- Error from top-level task
   assert(not pcall(thread.dispatch, error, 'a'))
end
ce1()


-- >> Catch an exception thrown from a task using thread.join.

local function ce2()
   -- Error caught by join
   local function f()
      local th = thread.new(error, 'yikes')
      assert(not pcall(thread.join, th))
   end
   thread.dispatch(f)
end
ce2()


-- >> Catch exceptions missed by thread.join()

local function ce3()
   -- Error caught by dispatch
   local function g()
      local th = thread.new(error, 'yikes')
      thread.join(th)
   end
   assert(not pcall(thread.dispatch, g))
end
ce3()

local t = xpio.gettime()
run( {1, 3, 5}, ts1 )
assert(xpio.gettime() >= t + 0.05)

