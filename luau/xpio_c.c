// XPIO: Cross-Platform I/O APIs for Lua
//
// See xpio.txt for documentation.
//
// TODO:
//
//   * writev(<stringtable> [,pos]) -->  count, total
//      stringtable = string | array of stringtables

#define _GNU_SOURCE // on Linux, _POSIX_C_SOURCE does not pull in waitpid()

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <sys/errno.h>
#include <sys/socket.h>
#include <sys/resource.h>
#include <netinet/in.h>
#include <netinet/tcp.h>  // TCP_NODELAY
#include <fcntl.h>
#include <poll.h>

#include <signal.h>

#ifdef _WIN32
/* ? */
#else
#  include <unistd.h>
#endif

#include "lualib.h"
#include "lauxlib.h"
#include "xlua.h"

#define BAIL_IF(expr)  if (expr) { goto bail; }

#define FREE_IF(expr)  if (expr) { free( (expr) ); }

#define ARRAY_LENGTH(a)  (sizeof (a) / sizeof (a)[0])

#define ZERO_REC(r)  (memset(&(r), 0, sizeof (r)))

#define SLL_DEQUEUE(ptr, head, T, next)                  \
   {  T **__pp = &(head);                                \
      for (;*__pp; __pp = &(*__pp)->next) {              \
         if (*__pp == (ptr)) {                           \
            *__pp = (ptr)->next;                         \
            break;                                       \
         }                                               \
      }                                                  \
   }

// iterate over table. Inside loop, key is at -2, value is at -1.
#define FOR_PAIRS(L, ndx) \
   for (lua_pushnil((L)); lua_next((L), (ndx)) != 0; lua_pop((L), 1))


//----------------------------------------------------------------
// utilities
//----------------------------------------------------------------

// Initial size for growable arrays.
#define INITIAL_SIZE 16


// POSIX demands read/modify/write in all cases
//
static int fcntl_mod_FL(int fd, int flagsAdd, int flagsRemove)
{
   int flags = fcntl(fd, F_GETFL);
   if (flags != -1) {
      flags = fcntl(fd, F_SETFL, (flags & ~flagsRemove) | flagsAdd);
   }
   return flags;
}


// POSIX fail: fcntl() is now the only way to mark sockets non-blocking,
// although fcntl docs say "This facility is only required for regular
// files because it is not appropriate for many devices such as terminals
// and network connections." Here's hoping implementors don't read the
// specs too closely?

// POSIX fail: Non-blocking status is a file property (not a descriptor
// property) so this may affect other processes holding the same
// descriptor. [Another obstacle to composability.]

// Returns -1 on error; 0 on success.
//
static int setNonBlocking(int fd, int bOn)
{
   int flagsAdd = 0;
   int flagsRemove = 0;

   if (bOn) {
      flagsAdd = O_NONBLOCK;
   } else {
      flagsRemove = O_NONBLOCK;
   }

   return fcntl_mod_FL(fd, flagsAdd, flagsRemove);
}


// Returns -1 on error; 0 on success.
//
static int getNonBlocking(int fd, int *pbOn)
{
   int flags = fcntl(fd, F_GETFL);
   if (flags == -1) {
      *pbOn = 0;
      return -1;
   }
   *pbOn = (flags & O_NONBLOCK) && 1;
   return 0;
}


// Grow dynamically allocated array (NULL == unallocated), copying
// old values and zero-filling the rest.
//   *plen = number of elements allocated (in/out)
//   size = size of elements
//   ndx = index to be used
//
// On success, return new pointer and set *plen to new length.
// On failure, return old pointer and leave *plen unchanged.
//
static void *
growArray(void *ptr, int *plen, size_t size, int lenMin)
{
   void *pNew;
   int len = *plen;
   int lenNew;

   if (lenMin < len) {
      return ptr;
   }

   lenNew = lenMin * 2;
   pNew = malloc(lenNew * size);
   if (!pNew) {
      return ptr;
   }

   memcpy(pNew, ptr, len * size);
   memset(((char*)pNew) + (len*size), 0, (lenNew - len) * size);
   if (ptr) {
      free(ptr);
   }
   *plen = lenNew;
   return pNew;
}


static int tointegerDefault(lua_State *L, int ndx, int dflt)
{
   int value, isNum;
   value = lua_tointegerx(L, ndx, &isNum);
   return isNum ? value : dflt;
}



static int lengthOf(lua_State *L, int ndx)
{
   int len;
   lua_len(L, ndx);
   len = lua_tointeger(L, -1);
   lua_pop(L, 1);
   return len;
}


static unsigned checkUInt(lua_State *L, int ndx)
{
   lua_Number num = luaL_checknumber(L, ndx);
   if (! (num >= 0)) {
      return luaL_error(L, "xpio: invalid argument #%d", ndx);
   }
   if (num > UINT_MAX) {
      return UINT_MAX;
   }
   return (unsigned) num;
}


#define isDigit(ch)    (((unsigned) (ch) - (unsigned) '0') <= (unsigned) 9)

static int isRetry(int e)
{
   return e == EAGAIN ||
      e == EWOULDBLOCK ||
      e == EINTR ||
      e == EINPROGRESS ||
      e == EALREADY;
}


static const char *
scanNum(const char *pszNum, unsigned *pn)
{
   const char *psz = pszNum;
   unsigned n = 0;
   while (isDigit(*psz)) {
      n = n *10 + (*psz - '0');
      ++psz;
   }
   *pn = n;
   return psz;
}


// Initialize a sockaddr_in from a string representation
//
static int addrFromString(struct sockaddr_in *psin, const char *psz)
{
   unsigned nums[4] = {0};
   unsigned port = 0;
   size_t i;

   for (i=0; ; ++i) {
      if (!*psz) {
         break;
      }
      if (*psz == ':') {
         psz = scanNum(psz+1, &port);
         break;
      }
      if (i >= ARRAY_LENGTH(nums)) {
         return -1;
      }
      psz = scanNum(psz, &nums[i]);
      if (*psz == '.') {
         ++psz;
      }
   }

   // TODO: syntax validation
   // TODO: range validation

   // POSIX fail: I can find no specifications or docs (POSIX, Linux,
   // MacOS) that indicate to zero the unused fields, but trial and error
   // indicates that it is necessary (at least on MacOS).
   ZERO_REC(*psin);

   if (i > 1) nums[0] *= 0x1000000;
   if (i > 2) nums[1] *= 0x10000;
   if (i > 3) nums[2] *= 0x100;

   // POSIX fail: Port and addr are typed as numbers *yet* stored in network
   // byte order, requiring htons/htonl (still...).
   psin->sin_family = AF_INET;
   psin->sin_addr.s_addr = htonl(nums[0] + nums[1] + nums[2] + nums[3]);
   psin->sin_port = htons(port);
   return 0;
}


//--------------------------------
// socket options
//--------------------------------

typedef struct {
   const char *str;
   int type;
   int category;
   int level;
   int name;
} SockOpt;

// types
#define SOCKOPT_BOOL 1    // nil/false or true/...
#define SOCKOPT_SIZE 2    // non-negative integer

// categories
#define SOCKOPT_SO  1
#define SOCKOPT_NB  2


static const SockOpt opts[] = {
   { "TCP_NODELAY",  SOCKOPT_BOOL, SOCKOPT_SO, IPPROTO_TCP, TCP_NODELAY  },
   { "SO_KEEPALIVE", SOCKOPT_BOOL, SOCKOPT_SO, SOL_SOCKET,  SO_KEEPALIVE },
   { "SO_REUSEADDR", SOCKOPT_BOOL, SOCKOPT_SO, SOL_SOCKET,  SO_REUSEADDR },
   { "SO_RCVBUF",    SOCKOPT_SIZE, SOCKOPT_SO, SOL_SOCKET,  SO_RCVBUF    },
   { "SO_SNDBUF",    SOCKOPT_SIZE, SOCKOPT_SO, SOL_SOCKET,  SO_SNDBUF    },
   { "O_NONBLOCK",   SOCKOPT_BOOL, SOCKOPT_NB, 0,           0            },
   { 0, 0, 0, 0, 0 }
};


static const SockOpt *findSockOpt(const char *psz)
{
   const SockOpt *po = &opts[0];

   for (po = &opts[0]; po->str; ++po) {
      if (0 == strcmp(psz, po->str)) {
         return po;
      }
   }
   return NULL;
}

//--------------------------------
// Lua utils
//--------------------------------

static int pushError(lua_State *L, const char *pszFmt)
{
   lua_pushnil(L);
   lua_pushfstring(L, (pszFmt ? pszFmt : "%s"), strerror(errno));
   return 2;
}


// Create a new userdata with a metatable from the XPIO table
//
static void *xpio_newObject(lua_State *L, size_t size, const char *mtName)
{
   void *pv;

   lua_getfield(L, lua_upvalueindex(1), mtName);
   pv = xlua_newObject(L, -1, size);
   lua_remove(L, -2);

   return pv;
}

#define XPIO_NEWOBJECT(L, Type) \
   ((Type*) xpio_newObject((L), sizeof(Type), "_" #Type))



//----------------------------------------------------------------
// forward declarations
//----------------------------------------------------------------

// These xpproc functions are used by xpqueue
static int xpproc_isExited(lua_State *L, int ndxProc);
static int xpproc_reap(void);
static int xpproc_getSigPipe(void);

static int xpproc_dtor(lua_State *L);
static int xpproc_kill(lua_State *L);
static int xpproc_try_wait(lua_State *L);
static int xpproc_when_wait(lua_State *L);

static const luaL_Reg XPProc_regs[] = {
   {"__gc", xpproc_dtor},
   {"kill", xpproc_kill},
   {"try_wait", xpproc_try_wait},
   {"when_wait", xpproc_when_wait},
   {0, 0}
};




//----------------------------------------------------------------
// XPQueue
//----------------------------------------------------------------
//
// Each XPQueue userdata has a uservalue table:
//      uservalue[1] = readers: fd -> task
//      uservalue[2] = writers: fd -> task
//      uservalue[3] = child waiters: pid -> task

#define XPQUEUE_READ  1
#define XPQUEUE_WRITE 2
#define XPQUEUE_CHILD 3

typedef struct {
   struct pollfd* pfds;
   int            nfds;
} XPQueue;

static int xpqueue_dtor(lua_State *L);
static int xpqueue_wait(lua_State *L);
static int xpqueue_isEmpty(lua_State *L);

static const luaL_Reg XPQueue_regs[] = {
   {"__gc", xpqueue_dtor},
   {"wait", xpqueue_wait},
   {"isEmpty", xpqueue_isEmpty},
   {0, 0}
};


// Get task.queue.uservalue[mode] (the `readers` or `writers` table).
// Pushes three values: task.queue, uservalue, readers/writers.
//
static void xpqueue_tableFromTask(lua_State *L, int ndxTask, int mode)
{
   lua_getfield(L, ndxTask, "_queue");  // task.tqueue
   (void) XLUA_CAST(L, -1, XPQueue);    // validate queue
   lua_getuservalue(L, -1);
   lua_rawgeti(L, -1, mode);            // readers/writers
}


// De-queue a task that is currently registered as a reader or writer.
//
static int xpqueue_dequeue(lua_State *L, int mode)
{
   xpqueue_tableFromTask(L, 1, mode);
   lua_getfield(L, 1, "_dequeuedata");  // key = fd
   lua_pushnil(L);                      // value = nil
   lua_rawset(L, -3);                   // readers/writers[fd] = nil

   lua_pushnil(L);
   lua_setfield(L, 1, "_dequeue");      // task.dequeue = nil
   return 0;
}


static int xpqueue_dequeueR(lua_State *L)
{
   return xpqueue_dequeue(L, XPQUEUE_READ);
}


static int xpqueue_dequeueW(lua_State *L)
{
   return xpqueue_dequeue(L, XPQUEUE_WRITE);
}


static int xpqueue_dequeueC(lua_State *L)
{
   return xpqueue_dequeue(L, XPQUEUE_CHILD);
}


// Register a waiting task
//   ndxKey = index of fd (READ/WRITE) or xpproc (CHILD)
//   mode = XPQUEUE_READ, XPQUEUE_WRITE, XPQUEUE_CHILD
//
static int xpqueue_enqueue(lua_State *L, int ndxTask, int ndxKey, int mode)
{
   ndxTask = lua_absindex(L, ndxTask);
   ndxKey = lua_absindex(L, ndxKey);

   // assert(not task._dequeue)
   lua_getfield(L, ndxTask, "_dequeue");
   if (!lua_isnil(L, -1)) {
      luaL_error(L, "xpio: task scheduled twice");
   }

   // readers/writers/childWaiters[key] = task

   xpqueue_tableFromTask(L, ndxTask, mode);
   lua_pushvalue(L, ndxKey);   // key
   lua_pushvalue(L, ndxTask);  // value
   lua_rawset(L, -3);

   // task.dequeue = xpqueue_dequeue[R/W/C]

   lua_pushcfunction(L, (mode == XPQUEUE_READ ? xpqueue_dequeueR :
                         mode == XPQUEUE_WRITE ? xpqueue_dequeueW :
                         xpqueue_dequeueC));
   lua_setfield(L, ndxTask, "_dequeue");

   // task._dequeuedata = key

   lua_pushvalue(L, ndxKey);
   lua_setfield(L, ndxTask, "_dequeuedata");

   // leave 4 items on the stack
   return 0;
}


static int xpqueue_dtor(lua_State *L)
{
   XPQueue *me = XLUA_CAST(L, 1, XPQueue);
   if (me->pfds) {
      free(me->pfds);
      me->pfds = NULL;
      me->nfds = 0;
   }
   return 0;
}


// Make sure me->pfds[] is large enough to accommodate index `ndx`.
// Throw an error on failure.
static void XPQueue_ensureFDs(XPQueue *me, lua_State *L, int ndx)
{
   me->pfds = growArray(me->pfds, &me->nfds, sizeof(struct pollfd), ndx+1);
   if (ndx >= me->nfds) {
      luaL_error(L, "xpio: allocation failure");
   }
}


static void
XPQueue_wakeSockets(XPQueue *me, lua_State *L,
                    int ndxReady, int ndxReaders, int ndxWriters,
                    struct pollfd *pfds, int nfds)
{
   int n;
   int numTasks = lengthOf(L, ndxReady);

   ndxReady = lua_absindex(L, ndxReady);
   ndxReaders = lua_absindex(L, ndxReaders);
   ndxWriters = lua_absindex(L, ndxWriters);

   for (n = 0; n < nfds; ++n) {
      struct pollfd *pfd = pfds + n;

      if ((pfd->events & POLLIN) &&
          (pfd->revents & (POLLIN | POLLERR | POLLHUP | POLLNVAL))) {

         // readers[fd]._dequeue = nil
         // readyTasks[numTasks] = readers[fd]
         lua_rawgeti(L, ndxReaders, pfd->fd);
         lua_pushnil(L);
         lua_setfield(L, -2, "_dequeue");
         ++numTasks;
         lua_rawseti(L, ndxReady, numTasks);
         lua_pushnil(L);
         lua_rawseti(L, ndxReaders, pfd->fd);
      }

      if ((pfd->events & POLLOUT) &&
          (pfd->revents & (POLLOUT | POLLERR | POLLHUP | POLLNVAL))) {

         // writers[fd]._dequeue = nil
         // readyTasks[numTasks] = writers[fd]
         lua_rawgeti(L, ndxWriters, pfd->fd);
         lua_pushnil(L);
         lua_setfield(L, -2, "_dequeue");
         ++numTasks;
         lua_rawseti(L, ndxReady, numTasks);
         lua_pushnil(L);
         lua_rawseti(L, ndxWriters, pfd->fd);
      }
   }
}


static int
XPQueue_wakeChildWaiters(XPQueue *me, lua_State *L, int ndxReady, int ndxWaiters)
{
   int nTop = lua_gettop(L);
   int numReady = lengthOf(L, ndxReady);
   int numWaiting = 0;

   ndxReady = lua_absindex(L, ndxReady);
   ndxWaiters = lua_absindex(L, ndxWaiters);

   // enumerate waiters (process -> task)
   lua_pushvalue(L, ndxWaiters);
   for (lua_pushnil(L); lua_next(L, -2) != 0; lua_pop(L, 1)) {
      // xpproc is at -2;  task is at -1

      if (xpproc_isExited(L, -2)) {
         // put task in ready[]
         lua_pushvalue(L, -1);
         lua_rawseti(L, ndxReady, ++numReady);

         // mark task as not pending
         lua_pushnil(L);
         lua_setfield(L, -2, "_dequeue");

         // remove task from childWaiters
         lua_pushvalue(L, -2);
         lua_pushnil(L);
         lua_rawset(L, ndxWaiters);
      } else {
         ++numWaiting;
      }
      //printf("... wcw loop: %d, %d\n", numReady, numWaiting);
   }

   //printf("wakeChildWaiters: numWaiting=%d numReady=%d\n", numWaiting, numReady);

   {
      int cnt = 0;
      lua_pushvalue(L, ndxWaiters);
      for (lua_pushnil(L); lua_next(L, -2) != 0; lua_pop(L, 1)) {
         ++cnt;
      }
      //printf("wakeChildWaiters: %d waiters left\n", cnt);
   }

   lua_settop(L, nTop);
   return numWaiting;
}


// tqueue:isEmpty()
//
static int xpqueue_isEmpty(lua_State *L)
{
   int mode;
   int isEmpty = 1;

   lua_getuservalue(L, 1);

   for (mode = 1; mode <= 3; ++mode) {
      lua_rawgeti(L, -1, mode);
      lua_pushnil(L);
      if (lua_next(L, -2) != 0) {
         isEmpty = 0;
         break;
      }
      lua_pop(L, 1);
   }

   lua_pushboolean(L, isEmpty);
   return 1;
}


// tqueue:wait(timeout)
//
static int xpqueue_wait(lua_State *L)
{
   XPQueue *me = XLUA_CAST(L, 1, XPQueue);
   int ndxUser, ndxSlots;
   int numOut;
   int nfdsUsed = 0;
   int timeout;
   int mode;

   if (lua_toboolean(L, 2)) {
      double num = luaL_checknumber(L, 2) * 1000.0;
      if (num < 0) {
         timeout = 0;
      } else if (num > INT_MAX) {
         timeout = INT_MAX;
      } else {
         timeout = (int) num;
      }
   } else {
      timeout = -1;
   }

   // get user value
   lua_getuservalue(L, 1);
   ndxUser = lua_gettop(L);

   // create "slots" table:  fd -> index into pfd[]
   // not a long-lived table, so over-allocation is not a problem
   lua_createtable(L, INITIAL_SIZE, 0);
   ndxSlots = lua_gettop(L);

   // construct pfds[] from readers and writers.  First add readers,
   // allocating slots in pfds[] and recording the index used for each fd.
   // Then add writers, allocating slots for each fd only when one has not
   // allready been allocated for a reader.

   for (mode = XPQUEUE_READ; mode <= XPQUEUE_WRITE; ++mode) {

      // get readers or writers
      lua_rawgeti(L, ndxUser, mode);

      for (lua_pushnil(L); lua_next(L, -2) != 0; lua_pop(L, 1)) {
         // key is at -2;  value is at -1
         int fd = lua_tointeger(L, -2);
         int ndxFD = 0;
         int bAllocated = 0;

         // see if there is already a slot for this fd
         if (mode == XPQUEUE_WRITE) {
            lua_rawgeti(L, ndxSlots, fd);
            ndxFD = lua_tointegerx(L, -1, &bAllocated);
            lua_pop(L, 1);
         }

         //printf(">> mode=%d fd=%d ndxFD=%d bAllocated=%d\n", mode, fd, ndxFD, bAllocated);
         // allocate a slot
         if (!bAllocated) {
            XPQueue_ensureFDs(me, L, nfdsUsed);
            ndxFD = nfdsUsed++;
            me->pfds[ndxFD].fd = fd;
            me->pfds[ndxFD].events = (mode == XPQUEUE_READ ? POLLIN : POLLOUT);
         } else {
            me->pfds[ndxFD].events |= POLLOUT;
         }

         // make note of the slot allocated for fd
         if (mode == XPQUEUE_READ) {
            lua_pushinteger(L, ndxFD);
            lua_rawseti(L, ndxSlots, fd);
         }
      }
   }

   lua_rawgeti(L, ndxUser, 3);  // childWaiters

   lua_newtable(L);  // result = array of ready tasks

   // stack: readers(-4) writers(-3) childWaiters(-2) ready(-1)

   // Move ready childWaiters to ready queue, and count pending ones
   int numChildWaiters = XPQueue_wakeChildWaiters(me, L, -1, -2);
   if (lengthOf(L, -1)) {
      timeout = 0;
   }

   if (numChildWaiters) {
      // wait on sigchldPipe
      // printf("... adding sigchldPipe to read set\n");
      XPQueue_ensureFDs(me, L, nfdsUsed);
      me->pfds[nfdsUsed].fd = xpproc_getSigPipe();
      me->pfds[nfdsUsed].events = POLLIN;
      ++nfdsUsed;
   }

   if (timeout == -1 && nfdsUsed == 0) {
      // nothing to wait on
      lua_pushnil(L);
      return 1;
   }

   do {
      //printf("poll(_, %d, %d) ...\n", nfdsUsed, timeout);
      numOut = poll(me->pfds, nfdsUsed, timeout);
      //printf("... poll -> %d\n", numOut);
   } while (numOut < 0 && errno == EINTR);
   if (numOut < 0) {
      return luaL_error(L, "xpio: poll error (%s)", strerror(errno));
   }

   XPQueue_wakeSockets(me, L, -1, -4, -3,
                       me->pfds, nfdsUsed - (numChildWaiters ? 1 : 0));

   if (numChildWaiters &&
       (me->pfds[nfdsUsed-1].revents & (POLLIN | POLLERR | POLLHUP | POLLNVAL)) &&
       xpproc_reap()) {
      (void) XPQueue_wakeChildWaiters(me, L, -1, -2);
   }

   return 1;
}


static int xpio_tqueue(lua_State *L)
{
   XPQueue *me = XPIO_NEWOBJECT(L, XPQueue);

   me->pfds = 0;
   me->nfds = 0;

   lua_createtable(L, 2, 0);             // uservalue
   lua_newtable(L);
   lua_rawseti(L, -2, XPQUEUE_READ);     // uservalue[1] = readers
   lua_newtable(L);
   lua_rawseti(L, -2, XPQUEUE_WRITE);    // uservalue[2] = writers
   lua_newtable(L);
   lua_rawseti(L, -2, XPQUEUE_CHILD);    // uservalue[2] = childWaiters
   lua_setuservalue(L, -2);

   return 1;
}


//----------------------------------------------------------------
// XPProc
//----------------------------------------------------------------

static int sigchldPipe[2] = { -1, -1 };

typedef struct XPProc {
   struct XPProc *next;
   int pid;               // PID until reaped; 0 after reaping
   int status;            // status after reaping
} XPProc;

// list of all XPProc instances
static XPProc *gpHeadProc = 0;

static XPProc *xpproc_new(lua_State *L);


// return 'read' side of the pipe
static int xpproc_getSigPipe(void)
{
   return sigchldPipe[0];
}


// POSIX fail: querying the status of a child process may have the side
//    effect of releasing the process (the PID -> process mapping may become
//    invalid).
//
// POSIX fail: PIDs are small integers and therefore precious, and failure
//    to reap a process promptly can lead to failure to create a new process.
//
//
// Our strategy:
//
// * Install a SIGCHLD handler that writes to `sigchldPipe`.
//
// * Add `sigchldPipe` to the readable set of poll/select when the
//   xpqueue has pending child waiters.
//
// * When `sigchldPipe` is indicated as readable by poll/select, consume the
//   pipe and reap all processes.  (This can happen only when there is a
//   child waiter on some XPQueue.)
//
// * When child processes are reaped, update their corresponding XPProc instance.
//
// Since the SIGCHLD handler is global, any XPQueue might end up reaping
// xpproc's that are waited for on other XPQueues. As a result, each
// xpqueue_wait() must poll all of its child waiters before poll/select, and
// then again after reaping.


static int xpproc_isExited(lua_State *L, int ndxProc)
{
   XPProc *me = XLUA_CAST(L, ndxProc, XPProc);
   return me->pid == 0;
}


// Consume the signal pipe, reap all exited processes, and return
// the number of xpproc objects that have been updated.
//
static int xpproc_reap(void)
{
   int numUpdated = 0;
   int n;
   int status;
   pid_t pid;
   char buf[32];
   int bReceived = 0;

   do {
      n = read(sigchldPipe[0], buf, sizeof buf);
      //printf("%d bytes from from signal pipe!\n", n);
      if (n > 0) {
         bReceived = 1;
      }
   } while (n == sizeof buf);

   if (!bReceived) {
      return 0;
   }

   // reap children
   do {
      pid = waitpid((pid_t)-1, &status, WNOHANG);
      //printf("waitpid -> pid=%d errno=%d\n", pid, errno);
      if (pid > 0) {
         // find and update process object
         XPProc *p;
         for (p = gpHeadProc; p; p = p->next) {
            if (p->pid == pid) {
               p->pid = 0;
               p->status = status;
               ++numUpdated;
               break;
            }
         }
      }
      // POSIX doesn't seem to explicitly disallow EINTER even with WNOHANG
   } while (pid > 0 || (pid == -1 && errno == EINTR));

   //printf("... numUpdatd = %d\n", numUpdated);
   return numUpdated;
}


static int xpproc_kill(lua_State *L)
{
   XPProc *me = XLUA_CAST(L, 1, XPProc);

   if (me->pid <= 0) {
      return pushError(L, "process not running");
   }

   if (kill(me->pid, SIGKILL) == -1) {
      return pushError(L, NULL);
   }

   lua_pushboolean(L, 1);  // success
   return 1;
}


// clean up before de-allocation
//
static int xpproc_dtor(lua_State *L)
{
   XPProc *me = XLUA_CAST(L, 1, XPProc);

   // dequeue from global list
   SLL_DEQUEUE(me, gpHeadProc, XPProc, next);

   if (me->pid) {
      (void) kill(me->pid, SIGKILL);
      me->pid = 0;
   }
   return 0;
}


static int xpproc_try_wait(lua_State *L)
{
   XPProc *me = XLUA_CAST(L, 1, XPProc);

   if (me->pid > 0) {
      lua_pushnil(L);
      lua_pushstring(L, "retry");
      //printf("... try_wait(%d) --> retry\n", me->pid);
      return 2;
   }

   //printf("... try_wait() --> %x\n", me->status);
   if (WIFEXITED(me->status)) {
      lua_pushstring(L, "exit");
      lua_pushinteger(L, WEXITSTATUS(me->status));
      return 2;
   } else if (WIFSIGNALED(me->status)) {
      lua_pushstring(L, "signal");
      lua_pushinteger(L, WSTOPSIG(me->status));
      return 2;
   } else {
      // exit status not ready
      return pushError(L, "retry");
   }

   // should not happen
   return pushError(L, "xpio: unexpected waitpid() result");
}


static void handleSIGCHLD(int sig)
{
   int n;
   int oldErrno = errno;
   //printf("SIGCHLD!\n");
   do {
      n = write(sigchldPipe[1], "\1", 1);
   } while (n == -1 && errno == EINTR);
   errno = oldErrno;
}


// perform this work when the module is first loaded
static void xpproc_init(void)
{
   static int initialized = 0;     // not MT-safe!
   struct sigaction sa;

   ZERO_REC(sa);
   if (!initialized) {
      initialized = 1;

      sa.sa_handler = handleSIGCHLD;
      sa.sa_flags = SA_RESTART;

      if (pipe(sigchldPipe)) {
         fprintf(stderr, "ERROR: pipe() failed: %d (%s)\n", errno, strerror(errno));
         return;
      }

      if (setNonBlocking(sigchldPipe[0], 1) == -1) {
         fprintf(stderr, "ERROR: failed to set pipe non-blocking\n");
         return;
      }

      if (sigaction(SIGCHLD, &sa, 0)) {
         fprintf(stderr, "ERROR: sigaction failed: %d (%s)\n", errno, strerror(errno));
         return;
      }
   }
}


static int xpproc_when_wait(lua_State *L)
{
   (void) XLUA_CAST(L, 1, XPProc);
   // printf("... when_wait\n");
   return xpqueue_enqueue(L, 2, 1, XPQUEUE_CHILD);
}


static XPProc *xpproc_new(lua_State *L)
{
   XPProc *me = XPIO_NEWOBJECT(L, XPProc);
   me->pid = 0;
   me->status = 0;

   me->next = gpHeadProc;
   gpHeadProc = me;

   xpproc_init();

   return me;
}


//----------------------------------------------------------------
// XPSocket
//----------------------------------------------------------------

typedef struct XPSocket {
   int s;
} XPSocket;

static int xpsocket_dtor(lua_State *L);
static int xpsocket_try_connect(lua_State *L);
static int xpsocket_try_accept(lua_State *L);
static int xpsocket_try_read(lua_State *L);
static int xpsocket_try_write(lua_State *L);
static int xpsocket_when_read(lua_State *L);
static int xpsocket_when_write(lua_State *L);
static int xpsocket_bind(lua_State *L);
static int xpsocket_listen(lua_State *L);
static int xpsocket_getsockname(lua_State *L);
static int xpsocket_getpeername(lua_State *L);
static int xpsocket_getsockopt(lua_State *L);
static int xpsocket_setsockopt(lua_State *L);
static int xpsocket_shutdown(lua_State *L);
static int xpsocket_close(lua_State *L);
static int xpsocket_fileno(lua_State *L);

static const luaL_Reg XPSocket_regs[] = {
   {"__gc", xpsocket_dtor},
   {"try_connect", xpsocket_try_connect},
   {"try_accept", xpsocket_try_accept},
   {"try_read", xpsocket_try_read},
   {"try_write", xpsocket_try_write},
   {"when_read", xpsocket_when_read},
   {"when_write", xpsocket_when_write},
   {"bind", xpsocket_bind},
   {"listen", xpsocket_listen},
   {"getsockname", xpsocket_getsockname},
   {"getpeername", xpsocket_getpeername},
   {"getsockopt", xpsocket_getsockopt},
   {"setsockopt", xpsocket_setsockopt},
   {"shutdown", xpsocket_shutdown},
   {"close", xpsocket_close},
   {"fileno", xpsocket_fileno},
   {0, 0}
};


static XPSocket *xpsocket_new(lua_State *L);


static int xpsocket_dtor(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);

   if (me->s) {
      close(me->s);
      me->s = -1;
   }
   return 0;
}


static int xpsocket_getXname(lua_State *L, struct sockaddr_in* psin)
{
   unsigned char *pby = (unsigned char *) &psin->sin_addr;

   if (psin->sin_family != AF_INET) {
      lua_pushnil(L);
      lua_pushfstring(L, "xpio: unknown address family %d", &psin->sin_family);
      return 2;
   }

   lua_pushfstring(L, "%d.%d.%d.%d:%d",
                   (int) pby[0],
                   (int) pby[1],
                   (int) pby[2],
                   (int) pby[3],
                   (int) (unsigned short) htons(psin->sin_port));
   return 1;
}


static int xpsocket_getsockname(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);
   struct sockaddr_in sin;
   socklen_t len = sizeof(sin);
   if (getsockname(me->s, (struct sockaddr*) &sin, &len))
      return pushError(L, NULL);
   return xpsocket_getXname(L, &sin);
}


static int xpsocket_getpeername(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);
   struct sockaddr_in sin;
   socklen_t len = sizeof(sin);
   if (getpeername(me->s, (struct sockaddr *) &sin, &len))
      return pushError(L, NULL);
   return xpsocket_getXname(L, &sin);
}


static int xpsocket_getsockopt(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);
   const char *psz = luaL_checkstring(L, 2);
   int nOpt;
   void *opt = (void*)&nOpt;
   socklen_t size = sizeof nOpt;
   int err;

   const SockOpt *po = findSockOpt(psz);
   if (!po) {
      lua_pushnil(L);
      lua_pushstring(L, "xpio: unknown socket option");
      return 2;
   }

   if (po->category == SOCKOPT_SO) {
      err = getsockopt(me->s, po->level, po->name, opt, &size);
   } else if (po->category == SOCKOPT_NB) {
      err = getNonBlocking(me->s, &nOpt);
   } else {
      return pushError(L, "getsockopt: internal error");
   }
   if (err) {
      return pushError(L, NULL);
   }

   if (po->type == SOCKOPT_BOOL) {
      lua_pushboolean(L, nOpt);
   } else if (po->type == SOCKOPT_SIZE) {
      lua_pushnumber(L, (lua_Number) nOpt);
   }
   return 1;
}


static int xpsocket_setsockopt(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);
   const char *optName = luaL_checkstring(L, 2);
   int nOpt;
   void *opt = (void*)&nOpt;
   int size = sizeof nOpt;
   int err;

   const SockOpt *po = findSockOpt(optName);
   if (!po) {
      lua_pushnil(L);
      lua_pushstring(L, "xpio: unknown socket option");
      return 2;
   }

   if (po->type == SOCKOPT_BOOL) {
      nOpt = lua_toboolean(L, 3);
   } else if (po->type == SOCKOPT_SIZE) {
      nOpt = checkUInt(L, 3);
   }

   if (po->category == SOCKOPT_SO) {
      err = setsockopt(me->s, po->level, po->name, opt, size);
   } else if (po->category == SOCKOPT_NB) {
      err = setNonBlocking(me->s, nOpt);
   } else {
      return pushError(L, "setsockopt: internal error");
   }
   if (err) {
      return pushError(L, NULL);
   }

   lua_pushboolean(L, 1);
   return 1;
}


static int xpsocket_try_accept(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);
   XPSocket *ps = xpsocket_new(L);

   ps->s = accept(me->s, NULL, NULL);
   if (ps->s == -1) {
      return pushError(L, isRetry(errno) ? "retry" : NULL);
   }

   // Linux: accepted socket does not inherit file status (the nerve!)
   if (setNonBlocking(ps->s, 1) == -1) {
      (void) close(ps->s);
      ps->s = -1;
      return pushError(L, NULL);
   }

   return 1;  // success => return new socket
}


static int xpsocket_try_read(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);
   size_t size = checkUInt(L, 2);
   luaL_Buffer b;
   int n;

   if (size == 0) {
      // POSIX fail: reading zero bytes may or may not test for error
      //   conditions on the socket (depending on implementation).  Here we
      //   avoid potential portability issues.
      lua_pushinteger(L, 0);
      return 1;
   }

   char *pbuf = luaL_buffinitsize(L, &b, size);

   n = read(me->s, pbuf, size);
   if (n >= (size ? 1 : 0)) {
      // success
      luaL_pushresultsize(&b, n);
      return 1;
   } else if (n == 0) {
      // end of stream
      lua_pushnil(L);
      return 1;
   } if (isRetry(errno)) {
      // wait for more
      return pushError(L, "retry");
   } else {
      // actual error
      return pushError(L, NULL);
   }
}


static int xpsocket_try_write(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);
   const char *data = luaL_checkstring(L, 2);
   int n;

   n = write(me->s, data, lua_rawlen(L, 2));
   if (n < 0) {
      return pushError(L, isRetry(errno) ? "retry" : NULL);
   }

   lua_pushinteger(L, n);
   return 1;
}


static int xpsocket_shutdown(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);
   const char *flags = luaL_checkstring(L, 2);

   // POSIX fail: You might think that SHUT_RDWR == SHUT_RD|SHUT_WR, but you
   // would be wrong.

   int shutr = strchr(flags, 'r') != NULL;
   int shutw = strchr(flags, 'w') != NULL;
   if (shutr || shutw) {
      int shut = (shutr && shutw ? SHUT_RDWR :
                  shutr ? SHUT_RD :
                  SHUT_WR);
      if (shutdown(me->s, shut)) {
         return pushError(L, NULL);
      }
   }
   lua_pushboolean(L, 1);   // success
   return 1;
}


static int xpsocket_close(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);
   if (me->s != -1) {
      close(me->s);
      me->s = -1;
      lua_pushboolean(L, 1);
      return 1;
   } else {
      return pushError(L, "already closed");
   }
}


static int xpsocket_fileno(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);
   lua_pushinteger(L, me->s);
   return 1;
}


static int xpsocket_bind(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);
   const char *addr = luaL_checkstring(L, 2);
   struct sockaddr_in sin;

   if (addrFromString(&sin, addr)) {
      return pushError(L, "xpio: mal-formed address argument");
   }
   if (bind(me->s, (struct sockaddr *) &sin, sizeof(sin))) {
      return pushError(L, NULL);
   }

   lua_pushboolean(L, 1);   // success
   return 1;
}


static int xpsocket_try_connect(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);
   const char *addr = luaL_checkstring(L, 2);
   struct sockaddr_in sin;
   int e;

   if (addrFromString(&sin, addr)) {
      return pushError(L, "xpio: mal-formed address");
   }
   e = connect(me->s, (struct sockaddr *)&sin, sizeof sin);

   // POSIX fail: Asynchronous connect oddness.  Instead of EAGAIN or
   // EWOULDBLOCK, we may get either EINPROGRESS or EALREADY to indicate
   // "try again later". Finally, success is indicated by another error code
   // EISCONN. Spec is unclear on whether an actual success result (return
   // value of 0) is possible, and on what the state of the sockaddr must be
   // on calls other than the first.

   if (e && errno != EISCONN) {
      return pushError(L, (isRetry(errno) ? "retry" : NULL));
   }

   lua_pushboolean(L, 1);   // success
   return 1;
}


static int xpsocket_listen(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);

   int nargs = lua_gettop(L);
   int backlog = 10;

   if (nargs > 1) {
      backlog = checkUInt(L, 2);
   }

   if (listen(me->s, backlog)) {
      return pushError(L, NULL);
   }

   lua_pushboolean(L, 1);   // success
   return 1;
}


static int xpsocket_when_read(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);
   lua_pushinteger(L, me->s);
   return xpqueue_enqueue(L, 2, -1, XPQUEUE_READ);
}


static int xpsocket_when_write(lua_State *L)
{
   XPSocket *me = XLUA_CAST(L, 1, XPSocket);
   lua_pushinteger(L, me->s);
   return xpqueue_enqueue(L, 2, -1, XPQUEUE_WRITE);
}


static XPSocket *xpsocket_new(lua_State *L)
{
   XPSocket *ps = XPIO_NEWOBJECT(L, XPSocket);
   ps->s = -1;

   return ps;
}


//----------------------------------------------------------------
// xpio functions
//----------------------------------------------------------------


// Create a socket, put it in non-blocking mode.
//
// On success, returns valid XPSocket and with the userdata on the stack.
// On failure, pushes `nil, <error>` on the stack and returns NULL.
//
static int xpio_socket(lua_State *L)
{
   XPSocket *me = xpsocket_new(L);
   const char *typeName = luaL_checkstring(L, 1);
   int type;

   if (0 == strcmp(typeName, "TCP")) {
      type = SOCK_STREAM;
   } else if (0 == strcmp(typeName, "UDP")) {
      type = SOCK_DGRAM;
   } else {
      lua_pushnil(L);
      lua_pushstring(L, "xpio: unsupported socket type");
      return 2;
   }

   me->s = socket(AF_INET, type, 0);
   if (me->s == -1) {
      return pushError(L, NULL);
   }

   // Note: *me and me->s will be cleaned up when userdata is collected

   if (setNonBlocking(me->s, 1) == -1) {
      return pushError(L, NULL);
   }

   return 1;   // success => return userdata
}


#define PAIR_PIPE   1
#define PAIR_SOCKET 2

static int xpio_pair(lua_State *L, int nPairType)
{
   XPSocket *psA = xpsocket_new(L);
   XPSocket *psB = xpsocket_new(L);
   int spOut[2];
   int n, err;

   if (nPairType == PAIR_PIPE) {
      err = pipe(spOut);
   } else {
      err = socketpair(AF_UNIX, SOCK_STREAM, 0, spOut);
   }

   if (err) {
      return pushError(L, NULL);
   }

   psA->s = spOut[0];
   psB->s = spOut[1];

   for (n = 0; n <= 1; ++n) {
      if (setNonBlocking(spOut[n], 1) == -1) {
         return pushError(L, NULL);
      }
   }

   return 2;
}


static int xpio_socketpair(lua_State *L)
{
   return xpio_pair(L, PAIR_SOCKET);
}


static int xpio_pipe(lua_State *L)
{
   return xpio_pair(L, PAIR_PIPE);
}


static int xpio_fdopen(lua_State *L)
{
   XPSocket *ps = xpsocket_new(L);

   // dup() creates a descriptor for the xpsocket to own (and close on
   // finalization). This avoids one xpsocket unpredictably closing a
   // descriptor used by another xpsocket.
   ps->s = dup((int) checkUInt(L, 1));
   if (ps->s == -1) {
      return pushError(L, NULL);
   }
   return 1;
}


static int xpio_gettime(lua_State *L)
{
   struct timeval tv;

   gettimeofday(&tv, (struct timezone *) NULL);

   lua_pushnumber(L, (double) tv.tv_sec + tv.tv_usec / 1.0e6);
   return 1;
}


// Return a NULL-terminated array of pointers to strings, or NULL.
// The array and all strings referenced by it are newly allocated.
//
static char **readStringArray(lua_State *L, int ndxArray)
{
   int numStrings = lengthOf(L, ndxArray);
   char **ptrs = (char**) calloc(numStrings + 1, sizeof(char*));
   if (!ptrs) {
      return NULL;
   }

   int offset = 0;
   for (offset = 0; offset < numStrings; ++offset) {
      lua_rawgeti(L, ndxArray, offset+1);
      size_t len;
      const char *pc = lua_tolstring(L, -1, &len);
      ptrs[offset] = pc ? strdup(pc) : NULL;
      lua_pop(L, 1);
      if (! ptrs[offset]) {
         break;
      }
   }

   return ptrs;
}


// nextfd(_, fdPrev) -->  fd
// Return the next open descriptor, or nil if there are no more.
//
static int xpio__nextfd(lua_State *L)
{
   struct rlimit rl;
   int fd = 0;
   int flags;
   int fdMax = -1;

   fd = tointegerDefault(L, 2, -1) + 1;

   if (fdMax < 0) {
      if (getrlimit(RLIMIT_NOFILE, &rl) < 0) {
         return luaL_error(L, "xpio: getrlimit failed");
      }
      // rlim_max is negative in OSX => use rlim_cur ?
      fdMax = rl.rlim_max - 1;
      if (fdMax < 0) {
         fdMax = rl.rlim_cur - 1;
      }
   }

   for (; fd <= fdMax; ++fd) {
      flags = fcntl(fd, F_GETFD);
      if (flags >= 0 && (flags & FD_CLOEXEC) == 0) {
         lua_pushinteger(L, fd);
         return 1;
      }
   }

   lua_pushnil(L);
   return 1;
}


// POSIX fail: Process-wide attributes are essentially global variables.
//   (signal handlers, current working directory, etc.)  This leads to
//   potentially unintended interactions between different components within
//   a process.


// POSIX fail: Non-hygeinic process creation APIs (fork and spawn)
//
//  * Process globals are inherited, not specified in process creation.
//    This requires code that spawns children to have knowledge of other
//    software in the same process that is involved in setting those process
//    globals (e.g. current working directory, etc.)
//
//  * The child process inherits the current set of file descriptors (versus
//    a specific set).


// POSIX fail: Over the years the UNIX `exec` call has mutated into several
//    different variants covering some, BUT NOT ALL, of the permutations of
//    of the following variants:
//      - argv[] provided as array *or* as vararg arguments
//      - envp[] is provided *or* not
//      - search path for command *or* require complete path to file


// Extract a action entry:  {fdTo, fdFrom}
// Return value = TRUE on success
//       *fdfrom = fd, or -1 if not given
//
static int
xpio_getAction(lua_State *L,
               int ndxActions,
               int indx,
               int *fdFrom,
               int *fdTo)
{
   lua_rawgeti(L, ndxActions, indx);
   if (!lua_istable(L, -1)) {
      lua_pop(L, 1);
      return 0;
   }

   lua_rawgeti(L, -1, 1);   // to
   lua_rawgeti(L, -2, 2);   // from
   *fdTo = tointegerDefault(L, -2, -1);
   *fdFrom = tointegerDefault(L, -1, -1);
   lua_pop(L, 3);

   return (*fdTo != -1);
}


// xpio._spawn(path, args, envStrings, fdActions) -> process | nil, error
//
//   path = path to executable file
//   args = array of strings; Lua args[1] == C argv[0]
//   envString = array of "NAME=VALUE" strings
//   fdActions = array of {fdTo, fdFrom} records, where fdFrom and fdTo are numbers.
//      {A, A}   => do nothing  + set A to non-blocking
//      {A, B}   => dup2(B, A)  + set A to non-blocking
//      {A, nil} => close(A)
//
static int xpio__spawn(lua_State *L)
{
   const char *path = luaL_checkstring(L, 1);
   luaL_checktype(L, 2, LUA_TTABLE);
   luaL_checktype(L, 3, LUA_TTABLE);
   luaL_checktype(L, 4, LUA_TTABLE);

   pid_t pid = fork();
   if (pid) {
      XPProc *pproc = xpproc_new(L);
      pproc->pid = pid;
      return 1;
   }

   // exec

   // reset signals

   // TODO: what about reversing SIG_IGN for SIGPIPE?
   sigset_t sigmask;
   sigemptyset(&sigmask);
   BAIL_IF(sigprocmask(SIG_SETMASK, &sigmask, NULL));

   // perform file actions

   int fdFrom, fdTo, ndx;
   for (ndx = 1; xpio_getAction(L, 4, ndx, &fdFrom, &fdTo); ++ndx) {
      if (fdFrom >= 0) {
         if (fdFrom != fdTo) {
            dup2(fdFrom, fdTo);
         }
         // make granted FDs blocking
         (void) setNonBlocking(fdTo, 0);
      } else {
         close(fdTo);
      }
   }

   char **argv = readStringArray(L, 2);
   char **envp = readStringArray(L, 3);

   execve(path, argv, envp);

 bail:
   exit(127);
}


// Create a table and populate it with environment variable names & values
//
extern char **environ;
static int xpio_getenv(lua_State *L)
{
   char **pstr;

   lua_newtable(L);

   char *str;
   for (pstr = environ; (str = *pstr) != NULL; ++pstr) {
      char *eq = strchr(str, '=');
      if (eq) {
         lua_pushlstring(L, str, eq - str);  // name
         lua_pushstring(L, eq + 1);          // value
         lua_rawset(L, -3);
      }
   }

   return 1;
}


static const luaL_Reg xpio_regs[] = {
   {"socket", xpio_socket},
   {"tqueue", xpio_tqueue},
   {"gettime", xpio_gettime},
   {"socketpair", xpio_socketpair},
   {"pipe", xpio_pipe},
   {"fdopen", xpio_fdopen},
   {"_spawn", xpio__spawn},
   {"_nextfd", xpio__nextfd},
   {0, 0}
};

extern int luaopen_xpio_c(lua_State *L);


int luaopen_xpio_c(lua_State *L)
{
   // POSIX fail: SIGPIPE will terminate a program when it writes to a socket
   // that a peer has closed, unless the program takes action to block or
   // ignore SIGPIPE. BSD provides SO_NOSIGPIPE, but that is not
   // portable. The following protects us from SIGPIPE, but it also disables
   // SIGPIPE behavior for stdin/stdout.  It is unfortunate to trigger
   // global side effects, but the default SIGPIPE behavior is essentially
   // incompatible with any network programming.
   signal(SIGPIPE, SIG_IGN);

   // create table
   lua_createtable(L, 0, ARRAY_LENGTH(xpio_regs)-1);

   // bind XPIO table to each function in a C closure, so they can
   // access the appropriate metatables for sockets, etc.
   xlua_register(L, -1, xpio_regs, -1);

   // create metatables

   XLUA_NEWMT(L, XPProc);
   lua_setfield(L, -2, "_XPProc");

   XLUA_NEWMT(L, XPQueue);
   lua_setfield(L, -2, "_XPQueue");

   XLUA_NEWMT(L, XPSocket);

   // make `socket:try_accept` a closure; it creates a socket
   lua_pushvalue(L, -2);
   lua_pushcclosure(L, xpsocket_try_accept, 1);
   lua_setfield(L, -2, "try_accept");

   lua_setfield(L, -2, "_XPSocket");

   // extract environment variables

   xpio_getenv(L);
   lua_setfield(L, -2, "env");

   return 1;
}
