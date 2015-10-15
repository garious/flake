#define _POSIX_C_SOURCE 200112L

#include <stdlib.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <sys/errno.h>

#include <dirent.h>

#include "lualib.h"
#include "lauxlib.h"
#include "sha1.h"

#define ARRAY_LENGTH(a) (sizeof(a) / sizeof((a)[0]))

#define SHA1_DIGEST_STRING_SIZE (SHA1_DIGEST_SIZE * 2)

static void digest_to_string(const uint8_t digest[SHA1_DIGEST_SIZE], char *c) {
    int i;
    for (i = 0; i < SHA1_DIGEST_SIZE; i++) {
       sprintf(c, "%02x", digest[i]);
       c += 2;
    }
    *c = '\0';
}

static int sha1_digest(lua_State* L) {
  SHA1_CTX ctx;
  uint8_t digest[SHA1_DIGEST_SIZE];
  char digestString[SHA1_DIGEST_STRING_SIZE + 1] = {0};
  size_t len = 0;
  const char* input = luaL_checklstring(L, 1, &len);

  SHA1_Init(&ctx);
  SHA1_Update(&ctx, (const uint8_t*) input, len);
  SHA1_Final(&ctx, digest);
  digest_to_string(digest, digestString);

  lua_pushlstring(L, digestString, SHA1_DIGEST_STRING_SIZE);
  return 1;
}

static const luaL_Reg sha1_regs[] = {
   {"digest", sha1_digest},
   {0,0}
};


extern int luaopen_sha1(lua_State *L);

int luaopen_sha1(lua_State *L)
{
   const luaL_Reg *preg;

   // create table
   lua_createtable(L, 0, ARRAY_LENGTH(sha1_regs));

   // push c functions into the table
   for (preg = &sha1_regs[0]; preg->func; ++preg) {
      lua_pushcfunction(L, preg->func);
      lua_setfield(L, -2, preg->name);
   }

   return 1;
}
