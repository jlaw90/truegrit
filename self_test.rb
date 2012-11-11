require_relative 'repo'
require_relative 'author'

repo = TrueGrit::Repo.new('.git', '.')

puts "Status output:"
pp repo.stage.status

repo.add('test') # Add the symlink to test committing behaviour
head = repo.head # Our HEAD
map = head.tree.map # A shitty) map of the file system at this point
repo.stage.restage
commit = repo.commit(TrueGrit::Author.new('James Lawrence', 'james@kukee.co.uk'),
                     'Lots and lots of changes including partial packfile report!
This was restaged and committed by truegrit
have a look in self_test.rb :D')

head = repo.head
tree = head.tree
parent = head.pare