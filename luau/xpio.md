# XPIO

Cross-platform Lua bindings for network and inter-process communication.

When the XPIO module is first loaded it will cause SIGPIPE signals to be
ignored in the calling process. This is important for performing network
communications because any writes to a socket could potentially generate
SIGPIPE, which would terminate the process by default. Unfortunately this
has global side effects -- programs participating in a pipeline reading from
actual pipes may be expected to exit in this condition.

Functions
===

xpio.socket(type)
---

Create a socket of the specified type. Supported types are `"TCP"` and
`"UDP"`. It returns the socket on success, or `nil, <error>` on failure.

See [[Socket Objects]], below.


xpio.tqueue()
---

Create a new task queue. Task queues keep track of `task` objects (Lua
tables) that are waiting for events.

Tasks are placed on the queue by [["When" Functions]].

[[`tqueue:wait(timeout)`]] returns the tasks whose events have occurred.


xpio.setCurrentTask(task)
---

Sets `task` as the current task.  The current task is used by
[[Blocking]] functions to schedule resumption of the running coroutine
before it yields.

xpio.getCurrentTask(task)
---

Returns the current task.


xpio.gettime()
---

Returns the current time in a format compatible with the timeout in
[[`tqueue:wait(timeout)`]].  Units are in seconds, and the reference
point is not specified.


xpio.socketpair()
---

Creates and returns two connected stream [socket objects] (#Socket
Objects). Data written to one is readable from the other and vice-versa.

On error, it returns `nil` and an error message.


xpio.fdopen(num)
---

Create and return a [socket object] (#Socket Objects) bound to a
specified file descriptor.  For example, `xpio.fdopen(1)` will return an
object that can be used to write to `stdout`.


xpio.pipe()
---

Creates a pipe and returns the two endpoints (read side followed by
write side).

On error, it returns `nil` and an error message.


xpio.spawn(args, env, files, attrs)
---

Create a new process, returning a process object (see [[Process
Objects]]).

 * `args` is an array of strings that describes the arguments for the
   new process. These strings `args[1...#args]` will be available to an
   invoked C program as `argv[0...argc-1]`.

   The first argument provides the default for `args.exe` (see below).

 * `env` is the environment for the new process in the form of a table
   mapping names to values. Environment names are case sensitive and may
   not contain `=` or null (`\0`) characters. Values may not contain
   null characters.

 * `files` is a sparse array describing what files will be granted to
   the new process.

   Each key in this table is a file number (descriptor) in the *child*
   process.  The value associated with each key identifies which of the
   parent's files will appear at that file number.  These can be file
   *objects* (created via `socket`, `fdopen`, `pipe`, etc.) or file
   numbers.  Any file *objects* provided will be closed in the parent
   process after the child process has been spawned.

   For example, in this case:

   ```lua
   { [0] = 0, [1] = 2, [2] = writePipe }
   ```

   the child's STDIN will be the same as that of its parent, its STDOUT
   will be the parent's STDERR, and its STDERR will be `writePipe`, and
   on success, `writePipe` will be closed in the parent process.

   All files granted to the child process will be reset to blocking
   mode, which is what most command-line programs will require.
   Unfortunately, due to OS limitations, the blocking/non-blocking
   property is a characteristic of the file, not of the process or the
   software using it, so after a file is passed to a child process it
   should not be directly accessed via XPIO's socket API.  (This is why
   granted file objects are closed.)

   Files granted to the child process will be reset to blocking mode,
   and will be closed in the current process.

 * `attrs` is a table mapping field names to values, all of which are
   optional:

    * `attrs.exe` gives the name of an executable file to be used as the
       code image for the child process.  If this value is `nil`,
       `args[1]` will be used.

       If the file name does not contain a "/", PATH is searched.

    * *[TODO]* `attrs.cwd` gives the current working directory for the
      child process.

    * *[TODO]* `attrs.pgroup`: When this value is a process object, it
      is the leader of a process group which the spawned process should
      be placed in. When this value is `true`, the spawned process will
      be placed in a new process group with itself as the leader.

Note that, unlike `posix_spawn()`, several values are *not* inherited
from the current process. The `file` argument explicitly names each
descriptor for the new process. Also, the signal mask and signal
handlers are set to defaults (using POSIX_SPAWN_SIGDEF).

Unresolved issues:

 * `umask` is inherited by the child process. `umask` is essentially an
   invisible input parameter to command-line tools, indicating how they
   are expected to create files, so in at least some contexts inheriting
   the parent's umask is the right thing.  An `attrs.umask` field could
   allow more control.

 * ctty (Controlling terminal) is inherited. This allows the process to
   gain access to the terminal by calling `open("/dev/tty")`.

 * Membership in process groups and sessions is inherited. This is
   probably the right thing for most server and client
   applications. Special programs like shells would call setsid() to
   make themselves a session leader, and assign new processes to
   pgroups.

 * Sandboxing: Specifying resource limits, new UID & groups, and related
   operations are not currently supported.


xpio.env
---

A table containing the environment variables of the current process.
This table is initialized when the xpio library is loaded.



Process Objects
===============

Methods
-------

process:kill()
---

Terminate execution of `process`.


process:wait()
---

Wait for the process to exit and return its exit status. It returns
one of the following values:

     +----------------------+-------------------------------------------+
     | `"exit", <num>`      | The process exited normally with status   |
     |                      | code <num>.                               |
     +----------------------+-------------------------------------------+
     | `"signal", <num>`    | The process was terminated by a signal,   |
     |                      | which is identified by <num>.             |
     +----------------------+-------------------------------------------+

This is a [[Blocking]] function that must be called from a coroutine.
Its corresponding "try" and "when" functions are `process:try_wait()`
and `process:when_wait()`.



Task Queue Objects
====================

tqueue:wait(timeout)
---

Wait until one or more tasks are ready.

Timeout is the maximum amount of time to wait, in seconds. A timeout
of `nil` or `false` means "no timeout".

If there are no tasks queued *and* there is no timeout, wait() returns
`nil`, indicating "nothing to wait on".

Otherwise, it returns an array that contains the tasks that are
ready to run. This array may be empty if the timeout expired before
any tasks were ready. All tasks returned will have been removed from
the tqueue, and their `_dequeue` field will be `nil`.


tqueue:isEmpty()
---

Return `true` if there are no tasks waiting in `tqueue`.


Socket Objects
==============

Socket objects are minimal wrappers around native file descriptors. I/O
operations are unbuffered, so performing small reads or writes will
negatively impact performance.

All these functions, except where noted, return `true` on success and report
error conditions by returning `nil, <error>`.  In the cases of error codes
`EAGAIN`, `EWOULDBLOCK`, `EINPROGRESS`, `EALREADY`, or `EINTR`, `<error>`
will be the string `"retry"`.  Otherwise, it will hold the string returned
from the C function `strerror()`.


Methods
-------

socket:bind(addr)
---

Bind socket to a local address. `addr` is a string in the [[Address
Format]] described below.

IP address 0 (or `0.0.0.0`) indicates "any interface" (POSIX's
`INADDR_ANY`). Port number 0 indicates "pick any available port".

socket:listen([backlog])
---

Listen for inbound TCP connections.

Backlog, if provided, is an integer giving the size of the accept queue.


socket:connect(addr)
---

Initiate a TCP connection, returning a new TCP object. `addr` is a
string in the [[Address Format]] described below.

This is a [[Blocking]] function that must be called from a coroutine.
Its "try" and "when" functions are `socket:try_connect()` and
`socket:when_write()`.


socket:accept()
---

Accept an incoming connection, returning a new socket. In "retry"
cases, the caller should retry when the socket is *readable*.

This is a [[Blocking]] function that must be called from a coroutine.
Its "try" and "when" functions are `socket:try_accept()` and
`socket:when_read()`.


socket:getsockname()
---

Get the bound local address of `socket`. On success, returns a string
in the XPIO's [[Address Format]].


socket:getpeername()
---

Get the IP address and port of the peer connected to `socket`. On
success, returns a string in the XPIO's [[Address Format]].


socket:close()
---

Close the socket.


socket:read(size)
---

`size` is the maximum number of bytes to be consumed.

    +---------------+-------------------+
    | Condition     | Return Value(s)   |
    +===============+===================+
    | success       | string            |
    +---------------+-------------------+
    | end           | `nil`             |
    +---------------+-------------------+
    | error         | `nil`, string     |
    +---------------+-------------------+

The "end" condition implies that the peer gracefully closed (or shutdown
writing) and all sent bytes have been received. In the error case, the
<string> returned is the result of strerror().

When `size` is zero, the function immediately returns an empty string;
no error conditions are reported. (This masks behavior undefined by
POSIX).

This is a [[Blocking]] function that must be called from a coroutine.
Its corresponding "try" and "when" functions are `process:try_read()`
and `process:when_read()`.


socket:write(data)
---

`data` is a string (or number) to be written to the socket.

    +-------------+------------------+
    | Condition   | Return Value(s)  |
    +=============+==================+
    | success     | number           |
    +-------------+------------------+
    | error       | `nil`, string    |
    +-------------+------------------+

On success the number of bytes written are returned. This might be
less than the size of data.  The "retry" condition indicates that the
caller should retry when the socket is writable.

When `data` is an empty string, the results are not clearly
defined. Refer to POSIX or specific implementations.

This is a [[Blocking]] function that must be called from a coroutine.
Its corresponding "try" and "when" functions are `process:try_write()`
and `process:when_write()`.


socket:getsockopt(option)
---

Query a socket option. See `xpio.setsockopt`, below.


socket:setsockopt(option, value)
---

Set a socket option.

`xpio.setsockopt` provides the functionality of `setsockopt`, `fcntl`,
and various other OS-level functions. Each option is named by a string
that corresponds to its POSIX name.

    +--------------------+-----------------------+
    | Option name        | Possible values       |
    +====================+=======================+
    | `"TCP_NODELAY"`    | boolean               |
    +--------------------+-----------------------+
    | `"SO_KEEPALIVE"`   | boolean               |
    +--------------------+-----------------------+
    | `"SO_REUSEADDR"`   | boolean               |
    +--------------------+-----------------------+
    | `"SO_RCVBUF"`      | non-negative integer  |
    +--------------------+-----------------------+
    | `"SO_SNDBUF"`      | non-negative integer  |
    +--------------------+-----------------------+
    | `"O_NONBLOCK"`     | boolean               |
    +--------------------+-----------------------+


socket:shutdown(what)
---

`what` is a string describing which end of the connection to shut
down. A `w` in the string means that writing will be shut down (the peer
will see and "end of stream" indication when it tries to read).  An `r`
in the stream will cause reading to be shut down.

socket:fileno()
---

Return the file descriptor number associated with `socket`.


Address Format
===

Addresses are returned as strings containing an IP address and the port
number, delimited by `:`. The IP address is supplied as four dot-delimited
decimal numbers.  For example:  `192.168.1.1:80`.

Addresses are accepted in the same format, and the following variations are
allowed:

 * The IP address may be supplied as a single number.

 * The IP address may be left empty, in which case it defaults to `0` (which
   is equivalent to `0.0.0.0`).

 * If the `:` is absent, or if it is followed by no other characters, the
   port number defaults to 0.

Examples:

```lua
s:bind("127.0.0.1")  -- bind to any available port on localhost
s:bind(":80")        -- bind to port 80 on all interfaces
```


Blocking
========

Several functions may "block" by suspending the current co-routine until
some external event such as I/O or child process termination. These
functions must be called while in a running co-routine.

Each such blocking function is accompanied by a "try" function and a "when"
function.

"Try" Functions
---------------

A "try" function's name is the blocking function with an added "try_" prefix.

A try function accepts the same arguments as the blocking function, and
returns the same values *except* that it also may return `nil, "retry"` when
the request cannot be immediately satisfied and the corresponding blocking
function would otherwise suspend the current coroutine.


"When" Functions
----------------

A "when" function's name is usually the name of the corresponding
blocking function with an added "when_" prefix. In some cases, however,
blocking functions can share a "when" function (e.g. `accept` and `read`
both build on `when_read`).

When functions accept a `task` object as a parameter and schedule the task
so that it will become ready when the corresponding "try" function should be
called again.  Task objects are Lua tables that typically contain
user-defined data.  Its contents are ignored by the queueing code except for
the following fields:

 * `task._queue` is the task queue on which a task should be scheduled.
   This should be assigned before calling a scheduling function.

 * `task._dequeue` is a function that will dequeue the task (prevent it from
   being returned from `tqueue:wait()`). This is assigned when the task is
   scheduled (by the "when" function) and should be `nil` when the task is
   not currently scheduled.

 * `task._dequeuedata` contains additional data that may be used by the
   `_dequeue` function (assigned when `_dequeue` is assigned).
