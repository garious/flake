local Op = require 'operator'

assert(Op.add(3,2) == 5)
assert(Op.sub(3,2) == 1)
assert(Op.mul(3,2) == 6)
assert(Op.div(3,2) == 1.5)
assert(Op.mod(3,2) == 1)
assert(Op.concat('a','b') == 'ab')

assert(Op.add(3,2) == 3+2)  -- |a,b| add(a,b) == a + b
assert(Op.sub(3,2) == 3-2)  -- |a,b| sub(a,b) == a - b
assert(Op.mul(3,2) == 3*2)  -- |a,b| mul(a,b) == a * b
assert(Op.div(3,2) == 3/2)  -- |a,b| div(a,b) == a / b
assert(Op.mod(3,2) == 3%2)  -- |a,b| mod(a,b) == a % b
assert(Op.concat('a','b') == 'a' .. 'b')

print "passed!"

