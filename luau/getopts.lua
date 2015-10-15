-- getopts
--
-- Getopts parses options from an array of command line words and constructs
-- a table mapping option names to their values.
--
-- Usage:   words, values = getopts.read(args, opts, ferr)
--
-- Arguments:
--     args = array of command line arguments (equivalent to the `arg`
--            array passed to the main Lua script)
--     opts = an array or a space-delimited list of strings that
--            describe option syntax.  (See below.)
--     ferr = (optional) a function that controls how errors are
--            handled.  If this function returns nil, getopts will
--            continue.  Refer to the source code for details.
--
-- Returns: words, values
--
--     words = an array of remaining (non-option) command arguments
--     values = a table mapping option names to option values.
--
-- Option syntax
--
--  * Arguments beginning with "-" are treated as options.
--
--  * Options that are not named in `opts` generate errors.
--
--  * Some options have arguments.  An argument follows the option as the
--    next word on the command line, or, in the case of options that begin
--    with "--", it may be appended to the option following a "=".
--
--  * Option processing stops at an argument exactly matching "--".  Any
--    following arguments are returned in `words`.
--
-- Supported options are described in `opts`, which is an array or a
-- space-delimited string of words.  Each word consists of names for the
-- option followed by a type specifier.
--
-- Option names are delimited by "/".  Each name includes its leading "-"
-- character(s) as it would appear on the command line.  The first of these
-- names, minus its leading dashes, gives the key that will be used in the
-- `values` table.  A name that does not begin with a dash will not match
-- any command line arguments, but can be provided as the first name to
-- specify the key.
--
-- The type specifier may be one of the following:
--
--   * The empty string indicates the option is a "flag" and has no arguments.
--     The value returned will be the number of times it occurs on the
--     command line, or nil if it never occurs.
--
--  * "=" specifies that the option expects an argument.  The value returned
--     will be the argument value (a string), or nil if the option does not
--     appear.  If the option occurs twice, an error is reported.
--
--   * "=*" specifies an option with an argument that may appear multiple
--     times.  The value returns will be an array of strings, or nil if the
--     option does not appear.
--
-- Some examples:
--
--   opts = "-v/--verbose"
--
--        This allows "-v" or "--verbose" to appear on the command line.
--        `values.v` will be non-nil if *either* of them appears.
--
--   opts = "noWarn/--no-warn=*"
--
--       This allows "--no-warn=<arg>" and "--no-warn <arg>".
--       `values.noWarn` will hold the result (an array or nil).
--
--   local files, o = getopts.read(arg, "-v/--verbose -o= -I=*")
--
--       Command line             files        o
--       -----------------------  ---------    -----------------------
--       "x y"                    {"x","y"}    {}
--       "-v --verbose"           {}           {v=2}
--       "-v x -I foo y -I=bar"   {"x","y}     {v=1, I={"foo","bar"}}
--

-- Parse option string
--
local function parseOpts(o)
   local opts = {}
   local f
   if type(o) == "string" then
      f = o:gmatch("([^%s]+)%s*")
   else
      local n = 0
      function f() n = n + 1; return o[n] end
   end
   for desc in f do
      local names, type = desc:match("([^:=]*)(:?=?%*?)")
      assert(names)
      local name = names:match("-*([^/]*)")
      for opt in names:gmatch("([^/]+)/?") do
         opts[opt] = { name=name, type=type }
      end
   end
   return opts
end

-- Process options, returning unprocesses options and remaining arguments
--
local function read(args, o, errhandler)
   local opts = parseOpts(o)
   local words, values = {}, {}
   local errfn = (type(errhandler) == "function" and errhandler or
               function (msg) error((errhandler or "getopts").. ": " .. msg) end)

   local argndx = 0
   local function nextArg()
      argndx = argndx + 1
      return args[argndx]
   end

   for a in nextArg do
      local opt, optarg = a:match("^(%-%-[^=]*)=(.*)")
      if not opt then
         opt, optarg = a:match("^(%-.*)"), false
      end
      if not opt then
         table.insert(words, a)
      else
         local o = opts[opt]
         if o then
            local v = values[o.name]
            if o.type ~= "" then
               -- has an argument
               optarg = optarg or nextArg()
               if not optarg then
                  local e = {errfn("Missing argument to "..opt, opt)}
                  if e[1] then
                     return table.unpack(e)
                  end
               end
               if o.type:match("%*") then
                  v = v or {}
                  values[o.name] = v
                  table.insert(v, optarg)
               elseif not v then
                  values[o.name] = optarg
               else
                  local e = {errfn("Argument repeated: " .. opt, opt)}
                  if e[1] then
                     return table.unpack(e)
                  end
               end
            else
               -- no argument; just count
               values[o.name] = (v or 0) + 1
            end
         elseif opt == "--" then
            -- stop option processing
            for a in nextArg do
               table.insert(words, a)
            end
            break
         else
            local e = {errfn("Unrecognized option: " .. a, a)}
            if e[1] then
               return table.unpack(e)
            end
         end
      end
   end

   return words, values
end


local G = {}
G.parseOpts = parseOpts
G.read = read
return G
