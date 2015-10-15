# XPFS Module

Overview
===

The `xpfs` module returns a table of functions for accessing the file system.

```lua
local xpfs = require "xpfs"
```

XPFS aims to enable Lua code that is portable across Windows and UNIX-based
operating systems.  Ideally, functionality should be provided in a way that
does not require the program to detect the underlying OS and implement
OS-specific code. When analogous functions exist on different OSes, the goal
is to expose them as consistently as possible.  When some functions or
features do not exist on all OSes, the goal is to allow clients to detect
the feature (rather than testing for the current OS and making an assumption
about the feature).


Functions
===


xpfs.chdir(dirname)
---

Change the current working directory of the current process.

The return value is `true` on success, `nil, <error>` on failure.


xpfs.chmod(filename, mode)
---

Modify the mode bits associated with a file.

`mode` is a string optionally beginning with "+" or "-", followed by any
number of characters denoting flags.

 * When `mode` begins with `+`, the named flags are added to the mode.

 * When `mode` begins with `-`, the named flags are removed from the
   mode.

 * Otherwise, the mode is set to the set of flags.

On UNIX-based systems this function provides a subset of POSIX
functionality: it modifies the "user" mode bits `r`, `w`, and `x`.

On Windows, the `w` it controls the "readonly" attribute of the file,
and the `r` and `x` bits are ignored.

Unrecognized flags are ignored.

The return value is `true` on success, `nil, <error>` on failure.


xpfs.dir(dirname)
---

Get the contents of directory `dirname`.

The return value is an array of strings on success, or `nil, <error>` on
failure.


xpfs.getcwd()
---

Return the name of the current working directory for the current
process, or `nil, <error>` on failure.


xpfs.mkdir(dirname)
---

Create a directory.

The return value is `true` on success, `nil, <error>` on failure.


xpfs.remove(filename)
---

Remove file `filename`.

`xpfs.remove` differs from `os.remove` in that it the "readonly" bit
will not prevent `xpfs.remove` from succeeded.

The return value is `true` on success, `nil, <error>` on failure.


xpfs.rename(from, to)
---

Rename the file or directory named `from` to `to`.

The return value is `true` on success, `nil, <error>` on failure.


xpfs.rmdir(dirname)
---

The return value is `true` on success, `nil, <error>` on failure.


xpfs.stat(filename, mask)
---

Retrieve file status.

`mask` is a string of characters specifying which fields are to be
populated in the returned table. To request a field, include the first
letter of the field name in the mask. The request all fields, include
`*` in the mask.  If `mask` *begins* with `L`, `lstat` will be used
instead of `stat` (on UNIXes).  Unrecognized mask characters are ignored.

If `mask` is not provided, it defaults to `"*"`.

On success, stat returns a table with zero or more of the following fields:

    +---------+---------------------------------------------------+
    | Field   | Value                                             |
    +=========+===================================================+
    | `atime` | time of last access                               |
    +---------+---------------------------------------------------+
    | `ctime` | time of last status change                        |
    +---------+---------------------------------------------------+
    | `dev`   | device number                                     |
    +---------+---------------------------------------------------+
    | `gid`   | group id (number)                                 |
    +---------+---------------------------------------------------+
    | `inode` | inode number                                      |
    +---------+---------------------------------------------------+
    | `kind`  | First letter of one of: file, directory, link,    |
    |         | pipe, char device, block device, socket, other.   |
    +---------+---------------------------------------------------+
    | `mtime` | time of last data modification                    |
    +---------+---------------------------------------------------+
    | `perm`  | POSIX mode bits: e.g. "rwxrw-r--"                 |
    +---------+---------------------------------------------------+
    | `size`  | file size                                         |
    +---------+---------------------------------------------------+
    | `time`  | max of mtime and ctime                            |
    +---------+---------------------------------------------------+
    | `uid`   | user id (number)                                  |
    +---------+---------------------------------------------------+

On error, stat returns `nil, <error>`.


Rationale
===

XPFS duplicates some functionality in `lfs` (LuaFileSystem) and the `os`
library.  XPFS provides functionality that is absent from either of those
(e.g. `chdmod`) or preferred to the existing implementations.  The remainder
of the (duplicative) file system functions require little additional code
and make `xpfs` complete, eliminating the need for `lfs`.

 * `chmod` is not provided by luafilesystem.

 * `xpfs.stat` versus `lfs.attributes`:

    1. LFS does not report mode (access rights) bits
    2. LFS does not allow you to query a subset of attributes.
    3. LFS annoyingly refers to file type (dir vs. file, etc.) as "mode"

 * Apps using `os.remove` may have to write OS-specific code, because it
   will fail *on Windows* when the readonly bit is set.  `xpfs.remove` will
   succeed as long as the running process has the ability to reset the
   readonly bit and remove the file.

 * `xpfs.dir` retrieves the entire directory in one call. This minimizes the
   number of open descriptors when traversing a directory tree, and
   minimizes runtime overhead and code size.

   `lfs.dir()` works as an iterator which means it throws errors instead of
   returning `nil, <error>`. This requires the use of pcall() in common
   cases.

   `xpfs.dir` may be extended in the future to support a `mask` attribute,
   allowing `stat` operations to be folded into the call. This would be
   particularly beneficial on Windows when requesting the `kind`
   property during `xpfs.dir`.

