require_relative 'repo'
require_relative 'author'

# I have a backup of my current git folder incase things fuck up
# I'd suggest you do the same if you're playing with this library :P
#if File.exists?('.git.bak')
#  require 'fileutils'
#  FileUtils.rm_rf('.git')
#  Dir.mkdir('.git')
#  FileUtils.cp_r('.git.bak/.', '.git')
#end

repo = TrueGrit::Repo.new('.')

head = repo.head

commits = repo.commits

tree = head.tree

pp tree

#repo.stage.restage
#commit = repo.commit(TrueGrit::Author.new('James Lawrence', 'james@kukee.co.uk'),
#                     'Even more packfile support (we support rebuilding deltas!) and optimisation
#Tags and submodules are the main things I want to add next
#After that I\'m not sure I\'ll need anything else as this should do what I need it to
#Again: This was self-staged and committed by truegrit (see self_test.rb)
#(Was pushed manually... for now ;))')

#repo.head.checkout('checkout_test')