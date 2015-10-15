local path = require 'path'

local P = path.new

assert(tostring(P'a.txt') == 'a.txt')
assert(P'a' .. P'b' == P'a/b')
assert(P'a' ..  'b' == P'a/b')


-- '..' is right associative
assert(P'a' ..  'b' ..  'c' == P'a/bc')  -- surprising?
assert(P'a' .. P'b' ..  'c' == P'a/b/c') -- better
assert(P'a' .. P'b' .. P'c' == P'a/b/c') -- best

assert(#(P'abc') == 3)

-- takeBaseName
assert(path.takeBaseName('file/test.txt') == 'test')
assert(path.takeBaseName('dave.ext') == 'dave')
assert(path.takeBaseName('') == '')
assert(path.takeBaseName('test') == 'test')
assert(path.takeBaseName('file/file.tar.gz') == 'file.tar')

-- takeDirectory
assert(path.takeDirectory('foo') == '.') -- Note: Haskell library would return ''
assert(path.takeDirectory('/foo/bar/baz')  == '/foo/bar')
assert(path.takeDirectory('/foo/bar/baz/') == '/foo/bar/baz')
assert(path.takeDirectory('foo/bar/baz')   == 'foo/bar')

-- takeFileName
assert(path.takeFileName('a.c') == 'a.c')
assert(path.takeFileName('test/') == '')

-- addExtension
assert(path.addExtension('file.txt',     'bib') == 'file.txt.bib')
assert(path.addExtension('file.',       '.bib') == 'file..bib')
assert(path.addExtension('file',        '.bib') == 'file.bib')
assert(path.addExtension('/',           'x')    == '/.x')

-- dropExtension
assert(path.dropExtension('file.txt') == 'file')
assert(path.dropExtension('file')     == 'file')

-- takeExtension
assert(path.takeExtension 'a'     == '')
assert(path.takeExtension 'a.c'   == '.c')
assert(path.takeExtension 'a.b.c' == '.c')

-- replaceExtension
assert(path.replaceExtension('file.txt',     '.bob') == 'file.bob')
assert(path.replaceExtension('file.txt',      'bob') == 'file.bob')       -- ext doesn't need '.'
assert(path.replaceExtension('file',         '.bob') == 'file.bob')       -- input doesn't need ext
assert(path.replaceExtension('file.txt',         '') == 'file')           -- add empty ext
assert(path.replaceExtension('file.fred.bob', 'txt') == 'file.fred.txt')  -- only last ext

print 'passed!'
