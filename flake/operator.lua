--
-- Functions for Lua's operators
--
return {
   first    = function(x)   return     x  end,
   unm      = function(x)   return    -x  end,
   add      = function(x,y) return x + y  end,
   sub      = function(x,y) return x - y  end,
   mul      = function(x,y) return x * y  end,
   div      = function(x,y) return x / y  end,
   mod      = function(x,y) return x % y  end,
   pow      = function(x,y) return x ^ y  end,
   concat   = function(x,y) return x .. y end,
   eq       = function(x,y) return x == y end,
   lt       = function(x,y) return x <  y end,
   le       = function(x,y) return x <= y end,
   index    = function(t,k) return t[k] end,
   call     = function(f,...) return f(...) end,
}

