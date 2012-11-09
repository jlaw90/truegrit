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
>require_relative 'repo'

Preamble
--------
I hope you can find some use of this library or at least find it interesting to examine, isses and pull requests are encouraged!