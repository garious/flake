# Thread Module

Overview
--------

The `thread` module returns a table of functions for creating and
manipulating independent suspendable threads of execution.

Each **thread** object owns a Lua **couroutine**, in which the thread's code
executes.  Threads keep track of other information that is needed for
scheduling the coroutine, stopping execution, and cleaning up resources.

In this document, "thread" refers to a thread instances created with this
library. These are not to be confused with OS threads (such as the one in
which the VM instance runs), or coroutine instances (for which the `type()`
function returns the string `"thread"`).

Generally, functions in the thread library must be called only from the
context of a suspendable thread, and not from the "main" thread.
[[`thread.dispatch(fn, ...)`]] is an exception: it creates a dispatch
context and a thread associated with that context. Any threads created using
`thread.new` automatically inherit the same dispatch context. (A typicaly
program has only one dispatch context.)


Functions
===

thread.new(fn, ...)
---

Create a new thread.

The new thread will begin execution by calling `fn(...)`.

The thread "exits" (ceases to execute) when the function runs to
completion and returns, or when `thread.kill` is used to kill the
function. When a thread exits, its `atExit` handlers are called.

This function returns a thread object.


thread.kill(thread)
---

Stop execution of the thread identified by `thread`. This will result in
any `atExit` handler being called.

If the thread has already exited, this has no effect.


thread.yield()
---

Temporarily suspend execution of the current thread to allow other
threads to execute.


thread.join(thread)
---

Wait for completion of the specified thread.

On completion, `join()` returns one of the following:

 * When a coroutine returns from the start function, the thread is said
   to exit "normally".  In this case, `join()` will return the values
   returned from the start function.

 * When a thread is killed before it returns normally, `join()` will
   return `nil, "killed"`.


thread.sleep(seconds)
---

Suspends execution of the thread until `seconds` seconds have elapsed.


thread.sleepUntil(time)
---

Suspends execution of the thread until the value returned by
`xpio.gettime()` is greater than or equal to `time`.


thread.atExit(fn, ...)
---

Enqueue `fn(...)` to be called when the thread terminates (returns from
its start function, or is killed).

This returns a value identifying the queued operation that can be later
passed to `cancelAtExit`.


thread.cancelAtExit(id)
---

Cancel a previously queued at-exit operation.

This returns `true` on success, or `nil` if the ID was not present in
the queue of at-exit operations.


thread.dispatch(fn, ...)
---

Create a dispatch context and a thread within that context, and enter a
dispatch loop. The new thread will be begin execution at `fn(...)` as in
[[`thread.new(fn, ...)`]].

The dispatch loop continues to execute until there are no ready treads
and no threads waiting on external events, at which point it returns to
the called.

Code executing within a dispatch context can call "blocking" functions,
including `thread.yield()`, `thread.sleep()`, and various functions in
`xpio` such as `socket:read()`. The dispatch loop transfers control to
ready threads in a round-robin fashion. It also monitors any external
events (e.g. data arriving on a socket) on which threads are waiting,
and makes the corresponding thread runnable when its event occurs.  When
there are no ready threads but there are threads waiting on external
events (e.g. data on a socket), the loop will block the OS thread
waiting on one of the external events.

`dispatch()` calls can be nested within other `dispatch()` calls. Each
invocation of dispatch will only dispatch threads that were created
within its own dispatch context.  This would be useful only in rare
situations in which you want to suspend execution of all other
coroutines in the VM.

