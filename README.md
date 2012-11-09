TrueGrit
========

About
-----
TrueGrit was written to provide git repository management to ruby applications without requiring a git executable.

By browsing the source you can hopefully get to grips with how git stores and manipulates its metadata (it's quite an interesting format)

**Note:** This is currently still in early development stages, API changes and refactorings will feature heavily and this should definitely **NOT** be considered production ready.

Features
--------
Currently supported:

* Repository creation (including bare repos)
* Checkout
* Clone (local to local)
* Commit
* Branching is supported but there is no front-end (can manually update HEAD and commit)

Unsupported:

* Merging
* Tagging (need to update the whole refs interface really)
* Remote management (need to add protocol support for git-over-http, git and ssh in future)

Examples
--------
Creating a repository
```ruby
require_relative 'repo'
repo = TrueGrit::Repo.init('.', false) # Create a repo in the current directory
                                       # second parameter is optional (defaults to false)
                                       # and indicates whether the repository should be bare
# Do whatever...
```

Opening a repository
```ruby
require_relative 'repo'
repo = TrueGrit::Repo.new('.git', '.') # Opens the git repository in .git and sets '.' as the working directory
                                       # Working directory is optional, if not specified then cannot commit, stage, etc.
```

Add a file to the staging area
```ruby
repo.add('file_name') # Where filename is your filename
                      # Likewise remove removes a file from the staging area and stops it being tracked
```

Restaging all files
```ruby
repo.stage.restage # Updates the staging area to contains the latest data from all files
                   # If you restage and then commit then the commited data will be the same as your working directory
```

Commit changes
```ruby
require_relative 'author'
repo.commit(TrueGrit::Author.new('James Lawrence', 'test@lol.com'), 'An example commit')
# This will commit all changes (even if there's no changes it'll still commit currently), and update HEAD to point
# to the new commit
```

Preamble
--------
I hope you can find some use of this library or at least find it interesting to examine.
Issues and pull requests are encouraged!