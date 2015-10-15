//----------------------------------------------------------------
// Lua utilities for exposing native objects to Lua and performing
// run-time type checking on values received from Lua.
//----------------------------------------------------------------
//
// Userdata type validation
// ------------------------
//
// Light usersdata contain a void pointer and have no metatable.
//
// Full userdata have:
//  - an allocated block of memory, recoverable with `lua_touserdata`
//  - a uservalue (table or nil), recoverable with `lua_getuservalue`
//  - a metatable, recoverable with `lua_getmetatable`
//
// When a C function is exported only as a "C closure" bound to a specific
// type of userdata, it can simply assume the type.
//
// When userdata values are passed as arguments from Lua code, C code must
// validate the type before using the pointer.  This validation is typically
// relies on the fact that Lua code cannot set the metatable of a userdata.
// The "standard" approach, supported by `luaL_checkudata`, uses this test:
//
//     REGISTRY[tname] == getmetatable(udata)
//
// The library supplies a globally unique string `tname`.  There can be only
// one metatable for each data type.  `luaL_newmetatable` creates and/or
// reuses the metatable when it is required.  If the library is loaded more
// than once, the instances end up sharing the same metatable -- effectively
// a global.
//
// XLUA validates using the following test:
//
//     REGISTRY[getmetatable(udata)] == tptr
//
// The library supplies `tptr`, which is a light userdata that holds the
// address of a the luaL_regs structure, which is guaranteed not to collide
// with any other module.  There can be multiple metatables for each C type
// (one per each instance of the library).  Each instance of the library
// keeps track of the metatables it creates, using C closures and/or
// uservalues.


#ifndef xlua_h
#define xlua_h

#include "lualib.h"
#include "lauxlib.h"


// Adds functions to the table at the top of the stack.  Does *not* modify
// the global environment.
//
// If `ndxUpValue` is non-zero, it identifies a value that will be bound to
// each function in a C closure.
//
static inline void
xlua_register(lua_State *L,
              int ndxTable,
              const luaL_Reg *regs,
              int ndxUpValue)
{
   const luaL_Reg *preg;

   ndxTable = lua_absindex(L, ndxTable);

   for (preg = regs; preg->func; ++preg) {
      if (ndxUpValue) {
         lua_pushvalue(L, ndxUpValue);
      }
      lua_pushcclosure(L, preg->func, (ndxUpValue ? 1 : 0));
      lua_setfield(L, ndxTable, preg->name);
   }
}


#define CONST_CAST(T)  (T) (uintptr_t) (const T)

static inline void
xlua_newMT(lua_State *L, const void *tptr)
{
   // mt = {}
   lua_createtable(L, 0, 0);

   // REGISTRY[mt] = regs
   lua_pushvalue(L, -1);
   lua_pushlightuserdata(L, CONST_CAST(void*) tptr);
   lua_rawset(L, LUA_REGISTRYINDEX);

   // mt.__index = mt
   lua_pushvalue(L, -1);
   lua_setfield(L, -2, "__index");

   // return mt
}


static inline void*
xlua_newObject(lua_State *L,
               int ndxMT,
               size_t size)
{
   void *me;

   ndxMT = lua_absindex(L, ndxMT);
   me = lua_newuserdata(L, size);  // stack: udata
   lua_pushvalue(L, ndxMT);        // stack: udata mt
   lua_setmetatable(L, -2);        // stack: udata
   return me;
}


static inline void*
xlua_checkudata(lua_State *L,
              int narg,
              const luaL_Reg *regs,
              const char *typeName)
{
   // if REGISTRY[getmetatable(udata)] == regs then
   //    return touserdata(udata)
   // else
   //    error(...)
   // end

   void *me = lua_touserdata(L, narg);

   if (me != NULL && lua_getmetatable(L, narg)) {
      lua_rawget(L, LUA_REGISTRYINDEX);
      void *tptr = lua_touserdata(L, -1);
      lua_pop(L, 1);
      if ((const void *)tptr == (const void*) regs) {
         return me;
      }
   }

   const char *msg = lua_pushfstring(L, "%s object expected, got %s",
                                     typeName, luaL_typename(L, narg));
   (void) luaL_argerror(L, narg, msg);
   return NULL;
}


//================================================
// Type-safe wrappers
//================================================


// Create a new metatable for userdatas, populate it with regs[], and
// associate it with &regs.
//
//  `Type` must be a data type that userdatas will hold.
//  `Type_regs` must be the name of an array of luaL_Reg structures.
//
#define XLUA_NEWMT(L, Type) \
   (xlua_newMT((L), (const void*) (Type##_regs)), \
    xlua_register((L), -1, (Type##_regs), 0))


// Create new userdata, given a metatable created by XLUA_NEWMT.
//
#define XLUA_NEWOBJECT(L, ndxMT, Type) \
   xlua_newObject((L), (ndxMT), sizeof(Type))


// Validate and extract a pointer to `Type` from a userdata.  Throw an error
// if the type does not match.
//
#define XLUA_CAST(L, ndxUData, Type) \
   ((Type *) xlua_checkudata((L), (ndxUData), Type##_regs, #Type))


#endif // xlua_h
