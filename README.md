The Flake Build System
======================

[![Join the chat at https://gitter.im/garious/flake](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/garious/flake?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

[![Build Status](https://travis-ci.org/garious/flake.svg)](https://travis-ci.org/garious/flake)

Introduction
------------

Flake is a build system that aims to replace Make.  Flake is a small,
portable, standalone executable and a general purpose build system.
Like Make, Flake has a slight bias towards its own implementation
language.  It is distributed with build rules for C/C++ and Lua.  In
conjunction with Clang or GCC, it can generate a standalone executable
with a single command-line invocation.


Beyond Make
-----------

* Flake does not invent its own programming language.  It reuses Lua.

  We chose Lua because it is simple, safe, portable and well-documented.

* Automatic parallelization.

  For example, consider the following build description.

  ```lua
  return c.program {
    c.object 'a.c',
    c.object 'b.c',
  }
  ```

  Flake recognizes that the program depends on 2 objects and that the
  objects are independent of each other.  It therefore builds the objects
  in parallel.  The C build rules have no special handling for this.
  Builders are only serialized with the output of one is the input of
  another.

* Build steps can have dependencies on dependency generators.

  ```lua
  return c.program(c.dependencies 'main.c')
  ```

* Flake build scripts do not specify dependencies between files.

  You will not see this:

  ```make
  %.o: %.c
  	clang -c -o $@ $<
  ```

  Flake dependencies are created implicitly.  Builders return a handle
  to any file that needs to be created.  Passing this handle to another
  function implies a dependency.

  ```lua
  local obj = c.object 'a.c'
  return c.program(obj)
  ```

* Names for intermediary files are automatically generated.

* Flake uses lexical scoping to track dependencies.  No global variables.

  No globals means that you can share build libraries between teams without
  concern for naming conflicts.

* Scales cleanly to multi-project builds.

  ```lua
  local mylib = flake.importBuild '../mylib'
  return c.program {
    'main.c',
    mylib.contents['mylib.a']
  }
  ```

  Flake builds subprojects in the context of the subproject's directory.
  Flake detects when relative paths are passed to/from the subproject
  and automatically adjusts the paths.  In the example above, the
  subproject builds `./mylib.a`, but the top-level project sees
  `../mylib/mylib.a`.  No need for `abspath()` noise.


Tutorial
========


Building flake from source
--------------------------

```bash
$ make -C flake
$ export PATH=$PWD/flake/out/release:$PATH
```

Use flake to build and run a C executable
-----------------------------------------

```bash
$ cat hello.c
#include <stdio.h>
int main() {
  printf("Hello, World!\n");
  return 0;
}
```

```bash
$ flake --silent c run hello.c
Hello, World!
```

Use flake to build and run a Lua executable
-------------------------------------------

```bash
$ cat hello.lua
print 'Hello, World!'
```

```bash
$ flake --silent lua run hello.lua
Hello, World!
```

Use flake and a Lua script to build multiple targets
----------------------------------------------------

```bash
$ cat build.lua
```

```lua
local system = require 'system'
local c      = require 'c'
local lua    = require 'lua'

return system.directory {
  path = 'out',
  contents = {
    ['hello-c']   = c.program{'hello.c'},
    ['hello-lua'] = lua.program{'hello.lua'},
  },
}
```

```bash
$ flake build.lua
```



Usage
=====

```
flake [OPTIONS]... [FILE [TARGET [TARGET_PARAMS]]]
```

Build the 'main' target from 'build.lua' in the current directory.

```bash
$ flake
```

Build the 'test' target from 'build.lua' in the current directory.

```bash
$ flake build.lua test
```

Build the 'main' target from 'foo.lua' in the current directory.

```bash
$ flake foo.lua
```

Build the 'main' target from 'build.lua. in the 'bar' directory.

```bash
$ flake -C bar
```


Credits
===

The Flake build system would not exist without the following contributions:

* Brian Kelley's [CFromLua](cfromlua) and [Luau](luau) libraries.
* Conal Elliott and Paul Hudak's research in Functional Reactive Programming.
* The authors of the [Lua](http://lua.org) programming language.
* The authors of the Make and SCons build systems.
* The sha1 implementation from [jbig2dec](git://git.ghostscript.com/jbig2dec).
