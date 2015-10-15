#
# Flake is built in 3 stages, each resulting in a Lua executable with
# additional functionality.
#
# Stage 1: Build a vanilla Lua executable.
#
#          $ cc lua/*.c -o lua
#
# Stage 2: Use the Stage 1 interpreter to build a Lua interpreter, called xplua,
#          that includes the C libraries used by flake (xpfs, xpio_c, and sha1)
#
#          $ lua cfromlua.lua interpreter.lua --open=xpfs,xpio_c,sha1 -o xplua.c
#          $ cc xplua.c xpfs.c xpio_c.c sha1.c -o xplua
#
# Stage 3: Use the Stage 2 interpreter to run the Flake build using Flake's main.lua.
#
#          $ xplua main.lua build.lua outdir=out/release
#

o=out/release
b=out/boot

luaPath  = $(shell pwd)/?.lua;../luau/?.lua
luaSrc = ../lua/lua-5.3.1/src
luaCs = $(wildcard $(luaSrc)/*.c)
luaNames = $(filter-out lua luac print,$(luaCs:$(luaSrc)/%.c=%))
xpluaCFiles = ../luau/xpio_c.c ../luau/xpfs.c ../sha1/sha1.c ../sha1/sha1_lua.c
LDFLAGS = -lm

all: flake

flake: $b/xplua main.lua build.lua
	LUA_PATH="$(luaPath)" $^ outdir=$o

$b/xplua: $b/xplua.c $(xpluaCFiles) $b/liblua.lib
	$(CC) -o $@ -O2 -I$(luaSrc) $^ $(LDFLAGS)

$b/xplua.c: $b/lua ../cfromlua/cfromlua.lua ../cfromlua/interpreter.lua
	$^ -o $@ --minify --open=xpfs --open=xpio_c --open=sha1

$b/lua: $(luaSrc)/lua.c $b/liblua.lib
	@mkdir -p $(@D)
	$(CC) -o $@ -O2 $^ $(LDFLAGS)

$b/liblua.lib: $(luaNames:%=$b/%.o)
	$(AR) rcs $@ $^

$(foreach x,$(luaNames),$(eval \
  $b/$x.o: $(x:%=$(luaSrc)/%.c) $b/.exists ; $(CC) -o $$@ -c -O2 -DLUA_USE_POSIX $$< \
))

%/.exists:
	@mkdir -p $(@D)
	@touch $@

clean:
	rm -rf $o $b .flake test/*/.flake

