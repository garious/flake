// XPFS: Lua Cross-Platform functions
//
// See xpfs.txt
//
// Wishlist:
//
// spawn & select : Because popen() cannot handle input AND output.
//
// realtime : clock_gettime(CLOCK_REALTIME, &ts)
//
// On Windows, support long paths using utf-8


#define _POSIX_C_SOURCE 200112L

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>

#ifdef _WIN32

#  include <io.h>
#  define chomd _chmod
#  define mode_t int

#  define lstat _stat   /* not supported on Windows */
#  define stat _stat
#  define S_ISDIR(m) (((m) & _S_IFDIR) != 0)
#  define S_ISREG(m) (((m) & _S_IFREG) != 0)
#  define S_ISBLK(m) 0   /* not supported on Windows */
#  define S_ISLNK(m) 0   /* not supported on Windows */
#  define S_ISCHR(m) 0   /* not supported on Windows */
#  define S_ISSOCK(m) 0   /* not supported on Windows */
#  define S_ISFIFO(m) 0   /* not supported on Windows */

#  include <direct.h>
#  include <errno.h>
#  define chdir _chdir
#  define mkdir(p,m) _mkdir(p)
#  define rmdir _rmdir

#  pragma warning(disable : 4996) // this covers POSIX and _CRT_SECURE_NO_DEPRECATE warnings

#else

#  include <unistd.h>
#  include <sys/errno.h>
#  include <dirent.h>

#endif


#include "lualib.h"
#include "lauxlib.h"

#define ARRAY_LENGTH(a) (sizeof(a) / sizeof((a)[0]))

#if defined(_MSC_VER) && _MSC_VER > 1300
   // this covers POSIX and _CRT_SECURE_NO_DEPRECATE warnings
#  pragma warning(disable : 4996)
   // conversion to/from lua_Number warnings
#  pragma warning(disable : 4244)
#endif


//----------------------------------------------------------------
// chmod(filename, mode)
//----------------------------------------------------------------

static int xpfs_chmod(lua_State *L)
{
   const char *filename = luaL_checkstring(L, 1);
   const char *szmode = luaL_checkstring(L, 2);
   int n;

	struct stat info;

   /* we only want to change user bits here, so get the current state */
	n = stat(filename, &info);
   if (n == 0) {
      mode_t MMM = info.st_mode;
      char pm = szmode[0];
      if (pm == '+' || pm == '-') {
         ++szmode;
      } else {
         #ifdef _WIN32
            MMM &= ~( _S_IREAD | _S_IWRITE );
         #else
            MMM &= ~S_IRWXU;
         #endif
      }

      for (; *szmode; ++szmode) {
         int bit = 0;
         #ifdef _WIN32
            if (*szmode == 'r') { bit = _S_IREAD; }
            if (*szmode == 'w') { bit = _S_IWRITE; }
         #else
            if (*szmode == 'r') { bit = S_IRUSR; }
            if (*szmode == 'w') { bit = S_IWUSR; }
            if (*szmode == 'x') { bit = S_IXUSR; }
         #endif
         if (pm == '-') {
            MMM &= ~bit;
         } else {
            MMM |= bit;
         }
      }
      n = chmod(filename, MMM);
   }

   if (n==0) {
      lua_pushboolean(L, 1);
      return 1;
   } else {
      lua_pushnil(L);
      lua_pushstring(L, strerror(errno));
      return 2;
   }
}

//----------------------------------------------------------------
// stat(filename, mask)
//----------------------------------------------------------------

// <st>.st_<nm>time as a double
//
// MacOS exposes st_Xtimensec, but that is not POSIX and the default file
// system only provides 1-second resolution.

#define DTIME(st, nm)  ((double) (st).st_##nm##time)

// store a time field into a Lua table at the top of the stack
#define STORETIME(st, nm, field)                                     \
   { lua_pushnumber(L, DTIME(st, nm)); lua_setfield(L, -2, field); }

#define MAX(a,b)  ( (a) > (b) ? (a) : (b) )


// Construct xpfs.stat() result on Lua stack.
//
static int do_stat(lua_State *L, const char *filename, const char *mask)
{
   const char *pch;
   int ch;
   int nerr;
   struct stat info;

   if (*mask == 'L') {
      nerr = lstat(filename, &info);
   } else {
      nerr = stat(filename, &info);
   }
   if (nerr != 0) {
      lua_pushnil(L);
      lua_pushstring(L, strerror(errno));
      return 2;
   }

   lua_createtable(L, 0, strlen(mask));

   for (pch = mask; (ch = *pch++) != '\0'; ) {

      if (ch == '*' || ch == 'p') {
         char perm[11];
         unsigned m = (unsigned) info.st_mode;
         int group;

         for (group = 2; group >= 0; --group, m >>=3) {
            perm[group*3 + 0] = ((m&4) ? 'r' : '-');
            perm[group*3 + 1] = ((m&2) ? 'w' : '-');
            perm[group*3 + 2] = ((m&1) ? 'x' : '-');
         }
         perm[9] = '\0';
         lua_pushstring(L, perm);
         lua_setfield(L, -2, "perm");
      }

      if (ch == '*' || ch == 'k') {
         const char *kind = (S_ISREG(info.st_mode) ? "f" :
                             S_ISDIR(info.st_mode) ? "d" :
                             S_ISLNK(info.st_mode) ? "l" :
                             S_ISBLK(info.st_mode) ? "b" :
                             S_ISCHR(info.st_mode) ? "c" :
                             S_ISSOCK(info.st_mode) ? "s" :
                             S_ISFIFO(info.st_mode) ? "p" :
                             "o");
         lua_pushstring(L, kind);
         lua_setfield(L, -2, "kind");
      }

      if (ch == '*' || ch == 's') {
         lua_pushnumber(L, (lua_Number) info.st_size);
         lua_setfield(L, -2, "size");
      }

      if (ch == '*' || ch == 't') {
         lua_pushnumber(L, MAX( DTIME(info, m), DTIME(info, c)) );
         lua_setfield(L, -2, "time");
      }

      if (ch == '*' || ch == 'm') {
         STORETIME(info, m, "mtime");
      }

      if (ch == '*' || ch == 'a') {
         STORETIME(info, a, "atime");
      }

      if (ch == '*' || ch == 'c') {
         STORETIME(info, c, "ctime");
      }

      if (ch == '*' || ch == 'i') {
         lua_pushnumber(L, (lua_Number) info.st_ino);
         lua_setfield(L, -2, "inode");
      }

      if (ch == '*' || ch == 'd') {
         lua_pushnumber(L, (lua_Number) info.st_dev);
         lua_setfield(L, -2, "dev");
      }

      if (ch == '*' || ch == 'u') {
         lua_pushnumber(L, (lua_Number) info.st_uid);
         lua_setfield(L, -2, "uid");
      }

      if (ch == '*' || ch == 'g') {
         lua_pushnumber(L, (lua_Number) info.st_gid);
         lua_setfield(L, -2, "gid");
      }
   }
   return 1;
}


static int xpfs_stat(lua_State *L)
{
   return do_stat(L, luaL_checkstring(L, 1), luaL_optstring(L, 2, "*"));
}


//----------------------------------------------------------------
// remove(filename)
//
// Unlike os.remove, we attempt to provide consistent semantics across
// UNIX/Windows.  Specifically, os.remove fails on "readonly" files in
// Windows, but not on UNIX when the user writable permission is false.
//
//----------------------------------------------------------------

static int xpfs_remove(lua_State *L)
{
   const char *filename = luaL_checkstring(L, 1);

   int nerr = remove(filename);

   #ifdef _WIN32
   if (nerr) {
      nerr = chmod(filename, _S_IWRITE | _S_IREAD);
      if (nerr == 0) {
         nerr = remove(filename);
         if (nerr) { chmod(filename, _S_IREAD); }
      }
   }
   #endif

   if (nerr) {
      lua_pushnil(L);
      lua_pushstring(L, strerror(errno));
      return 2;
   }

   lua_pushboolean(L, 1);
   return 1;
}


//----------------------------------------------------------------
// mkdir(dirname)
//----------------------------------------------------------------

static int xpfs_mkdir(lua_State *L)
{
   const char *dirname = luaL_checkstring(L, 1);

   if (mkdir(dirname, 0777)) {
      lua_pushnil(L);
      lua_pushstring(L, strerror(errno));
      return 2;
   }

   // success
   lua_pushboolean(L, 1);
   return 1;
}


//----------------------------------------------------------------
// rmdir(dirname)
//----------------------------------------------------------------

static int xpfs_rmdir(lua_State *L)
{
   const char *dirname = luaL_checkstring(L, 1);

   if (rmdir(dirname)) {
      lua_pushnil(L);
      lua_pushstring(L, strerror(errno));
      return 2;
   }

   // success
   lua_pushboolean(L, 1);
   return 1;
}


//----------------------------------------------------------------
// chdir(directory)
//----------------------------------------------------------------

static int xpfs_chdir(lua_State *L)
{
   const char *dirname = luaL_checkstring(L, 1);

   if (chdir(dirname)) {
      lua_pushnil(L);
      lua_pushstring(L, strerror(errno));
      return 2;
   }

   // success
   lua_pushboolean(L, 1);
   return 1;
}


//----------------------------------------------------------------
// getcwd()
//----------------------------------------------------------------

static int xpfs_getcwd(lua_State *L)
{
   char *dir = getcwd(NULL, 0);

   if (dir == NULL) {
      lua_pushnil(L);
      lua_pushstring(L, strerror(errno));
      return 2;
   }

   // success
   lua_pushstring(L, dir);
   free(dir);
   return 1;
}


//----------------------------------------------------------------
// rename(from, to)
//----------------------------------------------------------------

static int xpfs_rename(lua_State *L)
{
   const char *from = luaL_checkstring(L, 1);
   const char *to = luaL_checkstring(L, 2);;

   if (rename(from, to)) {
      lua_pushnil(L);
      lua_pushstring(L, strerror(errno));
      return 2;
   }

   // success
   lua_pushboolean(L, 1);
   return 1;
}


//----------------------------------------------------------------
// dir(dirname)
//----------------------------------------------------------------

#ifdef _WIN32

static int xpfs_dir(lua_State *L)
{
   int nargs = lua_gettop(L);
   const char *dirname = luaL_checkstring(L, 1);
   struct _finddata_t data;
   char *filespec;
   long h;
   int ndx = 0;
   int err;

   int len = strlen(dirname);

	if (len + 2  > _MAX_PATH) {
      lua_pushnil(L);
      lua_pushstring(L, "path too long");
      return 2;
   }

   filespec = malloc(len+3);
   if (!filespec) {
      goto bail_errno;
   }

   memcpy(filespec, dirname, len);
   memcpy(filespec + len, "/*", 3);

   h = _findfirst(filespec, &data);

   free(filespec);

   if (h == -1L) {
      goto bail_errno;
   }

   lua_createtable(L, 2, 0); // at least two entries
   do {
      lua_pushstring(L, data.name);
      lua_rawseti(L, -2, ++ndx);
      err = _findnext(h, &data);
   } while (err == 0);

   _findclose(h);

   if (errno != ENOENT) {
      goto bail_errno;
   }

   // success
   return 1;

 bail_errno:
   lua_pushnil(L);
   lua_pushstring(L, strerror(errno));
   return 2;
}

#else  /* not WIN32 */

static int xpfs_dir(lua_State *L)
{
   int nargs = lua_gettop(L);
   const char *dirname = luaL_checkstring(L, 1);
   struct dirent *pde;
   DIR *pdir;
   int ndx;

   if (nargs > 1) {
      (void) luaL_checkstring(L, 2);
   }

   pdir = opendir(dirname);
   ndx = 0;

   if (!pdir) {
      lua_pushnil(L);
      lua_pushstring(L, strerror(errno));
      return 2;
   }

   lua_createtable(L, 2, 0); // at least two entries

   while ( (pde = readdir(pdir)) != NULL ) {
      lua_pushstring(L, pde->d_name);
      lua_rawseti(L, -2, ++ndx);
   }

   closedir(pdir);

   // success
   return 1;
}

#endif


static const luaL_Reg xpfs_regs[] = {
   {"chmod", xpfs_chmod},
   {"stat", xpfs_stat},
   {"remove", xpfs_remove},
   {"mkdir", xpfs_mkdir},
   {"chdir", xpfs_chdir},
   {"rmdir", xpfs_rmdir},
   {"getcwd", xpfs_getcwd},
   {"rename", xpfs_rename},
   {"dir", xpfs_dir},
   {0,0}
};


LUAMOD_API int luaopen_xpfs(lua_State *L);

LUAMOD_API int luaopen_xpfs(lua_State *L)
{
   const luaL_Reg *preg;

   // create table
   lua_createtable(L, 0, ARRAY_LENGTH(xpfs_regs));

   // push c functions into the table
   for (preg = &xpfs_regs[0]; preg->func; ++preg) {
      lua_pushcfunction(L, preg->func);
      lua_setfield(L, -2, preg->name);
   }

   return 1;
}
