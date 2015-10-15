-- thread.lua
--
-- Thread.lua exports a number of functions that deal with "threads".  A
-- "thread" consists of a *task* and a *coroutine*.
--
-- Task Objects
-- -------------
--
-- Task objects represent a pending operation, and store the following:
--
--   * the dispatch context [needed to schedule a coroutine]
--   * what the coroutine is waiting on [needed to dequeue it]
--   * cleanup functions to be called when the coroutine exits
--   * values returned from the coroutine's start function
--
-- Dispatch Objects
-- ----------------
--
-- Dispatch objects represent a context for dispatching -- i.e. the state
-- associated with an invocation of `thread.dispatch()`.  When a task is
-- waiting on a blocking function -- e.g. read() -- it is stored in a queue
-- owned by its dispatch context. When a task is being executed, it is being
-- called (or resumed) from the instance of `dispatch()` associated with its
-- dispatch context.

local xpio = require "xpio"
local Heap = require "heap"
local Queue = require "queue"


-- reverse of table.pack
--
local function undoPack(t)
   return table.unpack(t, 1, t.n)
end


local thread = {}

-- currentTask holds the task currently executing
local currentTask


local function taskAtExit(me, fn, ...)
   local id = table.pack(fn, ...)
   table.insert(me.atExits, id)
   return id
end


local function taskCancelAtExit(me, id)
   for n = #me.atExits, 1, -1 do
      if id == me.atExits[n] then
         table.remove(me.atExits, n)
         return true
      end
   end
   return nil
end


local function taskRunAtExits(me)
   while true do
      local oe = table.remove(me.atExits)
      if not oe then return end
      oe[1](table.unpack(oe, 2, oe.n))
   end
end


local function taskDelete(me)
   if me._dequeue then
      me:_dequeue()
   end
   taskRunAtExits(me)
   me.dispatch.all[me] = nil
end


-- Task class
thread.Task = {}

-- Create a new task
--
-- Other task members not assigned herein:
--   me._dequeue
--   me._dequeuedata
--
local function taskNew(dispatch, fn, ...)
   local fargs = table.pack(...)
   local me = setmetatable({}, thread.Task)

   local function preamble()
      me.results = table.pack(xpcall(fn, debug.traceback, undoPack(fargs)))
      me.failed = not table.remove(me.results, 1)
      me.results.n = me.results.n - 1
      if me.failed then
         dispatch.all[me] = nil
      end
      taskDelete(me)
   end

   me.coroutine = coroutine.create(preamble)
   me.dispatch = dispatch
   me.atExits = {}
   me._queue = dispatch._queue
   me.makeReady = dispatch.makeReady

   me:makeReady()
   dispatch.all[me] = true
   return me
end


function thread.new(fn, ...)
   return taskNew(currentTask.dispatch, fn, ...)
end


function thread.yield()
   currentTask:makeReady()
   coroutine.yield()
end


local function joinWake(task)
   task._dequeue = nil
   task._dequeueTask = nil
   task._dequeueID = nil
   task:makeReady()
end


local function joinDequeue(task)
   taskCancelAtExit(task._dequeueTask, task._dequeueID)
   task._dequeue = nil
   task._dequeueTask = nil
   task._dequeueID = nil
end


function thread.join(task)
   if not task.results then
      local id = taskAtExit(task, joinWake, currentTask)
      currentTask._dequeue = joinDequeue
      currentTask._dequeueTask = task
      currentTask._dequeueID = id
      coroutine.yield()
   end
   if task.failed then
      error(task.results[1], 0)
   else
      return undoPack(task.results)
   end
end


function thread.atExit(fn, ...)
   return taskAtExit(currentTask, fn, ...)
end


function thread.cancelAtExit(id)
   return taskCancelAtExit(currentTask, id)
end


function thread.kill(task)
   if not task.results then
      task.results = table.pack(nil, "killed")
      taskDelete(task)
   end
end


-- Create a new "dispatch" (dispatching context)
--
local function newDispatch()
   local me = {}
   local ready = Queue:new()
   local sleepers = Heap:new()
   local tq = xpio.tqueue()

   me.all = {}  -- all unfinished tasks

   me._queue = tq

   local function dqQueue(task)
      task._dequeuedata:remove(task)
      task._dequeuedata = nil
      task._dequeue = nil
   end

   function me.makeReady(task)
      assert(not task._dequeue)
      task._dequeue = dqQueue
      task._dequeuedata = ready
      ready:put(task)
   end

   local function dqSleeper(task)
      sleepers:remove(task)
      task._dequeue = nil
   end

   function me.wakeAt(task, timeDue)
      assert(not task._dequeue)
      task._dequeue = dqSleeper
      task.timeDue = timeDue
      sleepers:put(task, timeDue)
   end


   function me:dtor()
      while true do
         local t = ready:first()
         if not t then break end
         taskDelete(t)
      end
   end


   function me:dispatch()
      local thisTask = currentTask
      local run = Queue:new()

      while true do
         --printf("%d readers, %d writers, %d sleepers\n",
         --     count(readers), count(writers), #sleepers, ready:length())

         -- Move ready tasks to the run queue, and then run them. During
         -- this time, any tasks placed on the ready queue will be run in
         -- the next iteration.

         run, ready = ready, run
         while true do
            currentTask = run:first()
            xpio.setCurrentTask(currentTask)
            if not currentTask then break end
            currentTask:_dequeue()

            local succ, err = coroutine.resume(currentTask.coroutine)
            if not succ then
               me:dtor()
               local msg = ("*** Uncaught error in thread:\n\t" .. tostring(err)):gsub("\n(.)", "\n | %1")
               error(msg, 0)
            end
         end

         local s = sleepers:first()
         local timeout = ready:first() and 0 or s and s.timeDue - xpio.gettime()
         local tasks = tq:wait(timeout)

         --printf("wait(%s) ->%s\n", tostring(timeout), tasks and #tasks or "nil")

         if tasks then
            for _, task in ipairs(tasks) do
               task:makeReady()
            end
         elseif not ready:first() then
            -- nothing to wait on
            break
         end

         -- wake sleepers
         local tNow = xpio.gettime()
         while true do
            local task = sleepers:first()
            if not task or task.timeDue > tNow then
               break
            end
            task:_dequeue()
            task:makeReady()
         end
      end

      currentTask = thisTask
      xpio.setCurrentTask(currentTask)
   end

   return me
end


function thread.dispatch(func, ...)
   local me = newDispatch()
   local t = taskNew(me, func, ...)
   me:dispatch()
   me:dtor()
   if t.failed then
      error(t.results[1], 0)
   end

   for task in pairs(me.all) do
      print("*** Dangling thread:")
      print(debug.traceback(task.coroutine))
   end
end


function thread.sleepUntil(t)
   currentTask.dispatch.wakeAt(currentTask, t)
   coroutine.yield()
end


function thread.sleep(delay)
   thread.sleepUntil(delay + xpio.gettime())
end


return thread
