require_relative 'repo'
require_relative 'author'

repo = TrueGrit::Repo.new('.git', '.')
#repo.add('test.txt')
#repo.stage.restage
status = repo.stage.status
commit = repo.commit(TrueGrit::Author.new('James Lawrence', 'test@lol.com'), 'Why marked as modified when theres no change?')

head = repo.head
tree = head.tree
parent = head.parent
pp parent # A change :O