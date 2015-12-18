# cfromlua

Description
===========

Cfromlua builds a C program from Lua sources.  It outputs a C source file
that implements `main()` and contains the required Lua sources stored as
character arrays. This C program can be compiled and linked with liblua.lib
to create a self-contained native executable.

Command Syntax
==============

    cfromlua [OPTION...] FILE...

Options
=======

`-o FILE`
----

Write the generated C code to `FILE`.

`-l MOD`
---

In the generated C code, load module `MOD` before invoking the main
module. This is analogous to the `-l MOD` option in the Lua
standalone interpreter, but in cfromlua the space between `-l` and
`MOD` is not optional.


`-b MOD`
---

Bundle module `MOD` into the generated C file, even if it is not
mentioned as a dependency of a named source file.

`-s MOD`
---

Skip (do not bundle) module `MOD` even if it is required by one of
the visited sources or named in a `-b` or `-l` option.

`--path=PATH` `--cpath=CPATH`
---

Use `PATH` as the value for `LUA_PATH`, or `CPATH` for
`LUA_CPATH`. This is additive with other `-I` and `--path`
arguments. See [[Dependency Scanning]].

`--open=LIB`
---

In the generated C code, initialize the native library `LIB` before
running `main()` by calling `luaopen_LIB()`.


`-I DIR`
---

Use "DIR/?.lua" as the LUA_PATH. This is additive with other `-I`
and `--path` arguments. See [[Dependency Scanning]].

`--minify`
---

Remove redundant whitespace and comments from the packaged
sources. Line breaks and local variables are left intact.

`-w`
---

Display a warning when a required file cannot be found.  The default
is to silently ignore modules that cannot be found.

`-Werror`
---

Treat warnings as errors (implies `-w`).


`-MF FILE`
---

Write dependencies to `FILE`.  See [[Generating Dependencies]].

`-MP`
---

Add an empty dependency line for each included file. See
[[Generating Dependencies]].

`-MT TARGET`
---

Specify the target for the dependencies. This is required when an
output file is not specified with `-o`. See [[Generating
Dependencies]].

`--`
---

Terminate options processing. All subsequent arguments will be
treated as module names even if they begin with `-`.

`-m NAME`
---

Specify the main() function name.

`-v`
---

Display module and file names as they are visited.


`-h` or `--help`
---

Display a summary of command usage.

`--readlibs`
---

Read implied library dependencies. When `--readdeps` is specified,
cfromlua operates in a different mode: it does not generate a C file
and it ignores most options.

In this mode, cfromlua *reads* a previously generated C file, whose
name is provided as an argument, and writes to stdout the list of
discovered native extension libraries (.lib, .o, etc.) that must be
linked with the generated executable. The `-M...` options are
supported and can be used to generate a makefile that describes
dependencies on the libraries.

`--luaout`
---

Generate a Lua source file instead of a C source file.

The Lua source file will contain all files referenced via `require`
and `requirefile`. All native module dependencies will be silently
ignored.


`--win`
---

Use "\" as a directory separator when writing out library
dependencies (with `--readlibs`).



Source Files
------------

Arguments that do not begin with `-` (or that follow `--`) are assumed to be
Lua source file names.  An argument name of `-` will pull its Lua source
contents from stdin.

Each named Lua source file will be bundled into the generated C file. That
is, its source will be included as a byte array that will be compiled when
the program runs.

The *first* Lua file named will be treated as the "main" module.  It will be
called when the program is run, with the global variable "arg" and "..." set
to the contents of `argv[]`.


Dependency Scanning
===================

Cfromlua will scan the specified Lua files for run-time dependencies,
looking for places in the sources where [`require`]
(http://www.lua.org/manual/5.2/manual.html#pdf-require) and
[[`requirefile`]] are called with constant strings.  It will find the
corresponding files in the search path and build them into the generated C
file as const byte arrays. At run time, `require` and `requirefile` will
load the bundled files instead of reading from the file system.

Detection of dependencies is based on a rudimentary static analysis. It
looks for occurrences of a `require` keyword followed by a string,
optionally in parentheses. Comments and the contents of literal strings are
ignored.

This technique has limitations. However, these limitations can be used to
our advantage, in order to control which files are bundled or not. For
example, you can cause cfromlua to omit some dependencies:

```lua
local rtrequire = require
local foo = rtrequire "foo"
```

Cfromlua will also treat the following `require` as indicating a dependency,
even though it might be rarely or never executed:

```lua
if condition then require("unused") end
```

This could be used in cases in which module names are computed at run time,
but there is a more efficient technique for that purpose. Cfromlua will
recognize the sequence `@require[file] NAME` *inside a comment*, where `NAME` is a
sequence of non-space characters.

```lua
-- @require abc   (bundle "abc.lua")
```

When searching for modules, cfromlua uses the values of `LUA_PATH` and
`LUA_CPATH`. It does *not* interpret `";;"` as "default path". Instead it
will ignore those path entries.

When a dynamic library is found in `LUA_CPATH`, a corresponding static
library or object file is expected in the same directory, named with a
different extension (`lib`, `a`, `o`, or `obj`).

The variables CFROMLUA_PATH and CFROMLUA_CPATH, if defined, will override
the corresponding LUA_PATH and LUA_CPATH values.  If one or more
`--path=...` or `-I` options are specified, environment variables are
ignored.


`requirefile`
-------------

Cfromlua makes assumptions about the meaning of `requirefile`, both as a
function name and a module name.

Functions named `requirefile` are assumed to locate and read a data file
from disk.  Cfromlua will locate and bundle any referenced files.  See
`luau/requirefile.lua` for complete documentation.

A module named `requirefile` is assumed to implement the above function.
Cfromlua will replace it with its own implementation (one that reads from
the bundled copies of the files).


Examples
========

Simple Program
--------------

Consider a Lua script and its dependencies: paths to search for included
modules, and perhaps a `-l`-loaded module. To invoke it in a way that
qualifies these dependencies, you can type:

```bash
$ export LUA_PATH=...luapath...
$ export LUA_CPATH=...luacpath...
$ lua -l a prog.lua ...args...
```

Cfromlua generates a C program that encapsulates these
dependencies. After compiling it you can invoke it with:

```bash
$ prog ...args...
```

To generate the C program, invoke cfromlua analogously to the Lua
interpreter:

```bash
$ export LUA_PATH=...luapath...
$ export LUA_CPATH=...luacpath...
$ cfromlua -l a prog.lua -o prog.c
```

When compiling, include the Lua VM headers in the include path, and lualib
in the link line:

```bash
$ cc -o prog prog.c ../lua/bin/liblua.lib -I../lua/inc
```

In the generated program, the `LUA_PATH` and `LUA_CPATH` environment
variables are ignored, *not* used as search paths. This helps to ensure when
tests are run that only the built-in dependencies are used. Otherwise the
program could easily work in the build system environment but fail when
deployed. The intent, after all, it to encapsulate all implied dependencies.


Standalone Interpreter
----------------------

If you want the Lua interpreter's handling of `-l` and `-e` options and
`LUA_PATH`, include `interpreter.lua`.  This can be used alone, or in
combination with other modules.

```bash
$ cfromlua -o mylua.c interpreter.lua
$ cc -o mylua mylua.c liblua.lib
```

In this case, `$ ./mylua <args>` would be equivalent to `$ lua <args>`.

```bash
$ cfromlua -o prog.c interpreter.lua prog.lua
$ cc -o prog prog.c prog.lua liblua.lub
```

In this case, `$ ./prog <args>` would be equivalent to `$ lua prog.lua
<args>`.


Generating Dependencies
-----------------------

Cfromlua can generate dependency files suitable for inclusion from Make.

To generate dependencies:

```bash
$ cfromlua -MF <depfile> -MT <outfile> -MP ...other args...
```

To generate dependencies *and* a C file in one invocation:

```bash
$ cfromlua -o <outfile> -MF <depfile> -MP ...other args...
```

`-MP` is optional, but it is almost always what you want.  While admittedly
awkward, this interface attempts to mimic that of gcc. See the gcc
documentation for more info on `-MF`, `-MT`, and `-MP`.


