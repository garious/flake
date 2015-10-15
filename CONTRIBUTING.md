Lua coding conventions
--------------------------------

* Names are generally initial-lower camel case.  This applies to local and
  member variables, regardless of type.

* Classes are named with initial upper case letters.

* Do not modify global variables.  Especially: Modules shall not modify or
  create any variables in _G when they are loaded by require().

  Lua modules each return a value, typically a table that includes all
  exported symbols.  Consumers of the modules assign a local name (which may
  be a shorter abbreviation).  For example:

  .   local xu = require "extrautils"

As always, exceptions apply.  Notably, since standard Lua library naming
uses all lower-case letters, modules that implement objects that are
interchangeable with Lua objects (files, for example), may use that style
for compatibility or consistency.


Other Coding Principles
--------------------------------

 * When implementing functions for others to consume, avoid mutation.  When
   possible, return newly created tables instead of modifying tables that
   were passed as input.  (Object methods and functions intended for
   construction of data structures are exceptions here.)

   Since tables may be referenced by other tables, modifying one table may
   have unknown ramifications throughout the code that can be extremely
   difficult to anticipate or debug, unless one follows a coding discipline.
   One approach is to duplicate data structures whenever a new reference is
   created, and freely use functions that mutate (e.g. table.sort).  Our
   preferred approach is to take special care when calling functions that
   mutate, and to copy references (relatively) freely.

 * Avoid Swiss-army-knife functions that serve multiple purposes based on
   the types and/or values of arguments.  If there are two different roles
   -- if the caller should "know" which operation it is requesting -- then
   give them two different function names.  Accidentally triggering the
   wrong role could lead to subtle bugs. Prefer functions that can be
   described simply.

 * Design APIs to minimize the need for calls to `type()`.

   For "sum types" or unions, tables are generally preferable, keyed on the
   presence/absence of fields.

   Returning values that require the caller to test types results in awkward
   usability, and can encourage to shortcuts that lead to bugs.


Philosophy
--------------------------------

Aim for the intersection of the following:

  clear: easy to understand completely, and in turn achieve correctness.
  simple: avoid feature bloat
  fast: executes quickly
  small: lightweight
