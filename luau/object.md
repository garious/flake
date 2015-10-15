# Object Module

Overview
===

The `object` module implements a simple object system.

```lua
local Object = require "object"
```

In this system, objects are Lua tables. Each object has a "parent"
object. Objects *inherit* properties and methods from their parent object,
which in turn inherits from its parent, and so on.

While this is usually called "class-less" or "prototype-based" inheritance,
its usage is analogous to class-based languages. Some objects will typically
be used to hold definitions of methods and common properties, while other
objects will hold only per-instance state.

For convenience, we use the term `class` to refer to objects that are
created for the purpose of serving as parents to other objects. (There is
little chance of confusion since actual class-based OO systems, while easily
implemented in Lua, are not commonly used.)

Classes typically inherit `new` and other methods from their parent and then
override `initialize` and add other method definitions.


Functions
===


Object:new(...)
---

Create and initialize a new object that is a child of `self`.

`self:initialize` is called with all the arguments that were passed to
`new`.


Object:initialize(...)
---

Initialize `self`.  This is called by `Object:new` after creating a new
object.


Object:basicNew()`
---

Create a new object that is a child of `self`, but do not initialize it.


Object:adopt(t)
---

Make `self` the parent of table `t`.


Object:getParent(parent)
---

Return the parent of `self`.


Example
----

```lua
local FIFO = Object:new()

function FIFO:initialize()
  self.t = {}
  self.indexWrite = 1
  self.indexRead = 1
end

function FIFO:put(item)
   self.t[self.indexWrite] = item
   self.indexWrite = self.indexWrite + 1
end

function FIFO:get()
   local n = self.indexRead
   if n < self.indexWrite then
       local item = self.t[n]
       self.indexRead = n + 1
       self.t[n] = nul
       return item
   end
   return nil
end

function FIFO:count()
   return self.indexWrite - self.indexRead
end


local fifo = FIFO:new()
fifo:put("A")
fifo:put("B")
print(fifo:get()) --> "A"
print(fifo:get()) --> "B"
print(fifo:get()) --> nil
```

In the above example, the parent of `fifo` is `FIFO`, and the parent of
`FIFO` is `Object`.  `Object` has no parent.

As with all module return values, `Object` itself should never be modified
by clients.


Details
===

Inheritance is achieved by setting the metatable of an object to its parent,
and by setting the `__index` metamethod of each parent to itself. This is
the approach described in *Programming in Lua*.

