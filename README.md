#### To obtain a running instance

`./run.sh` -> <http://localhost:8080/>

for the default blank test db, login as `admin` with password `password`

#### Dependencies

mzscheme: latest version of http://racket-lang.org/ with the appropriate folder added to `$PATH`

passlib: `easy_install passlib` might work

pandoc: `brew install pandoc` might work

node v0.10 (optionally inside a `nvm` added to your `$PATH` in your `~/.bashrc`)

#### What are files

part of arc

* ac.scm
* arc.arc
* as.scm: `./as.scm` gives an arc repl but is otherwise unused (& modified a tiny bit)
* brackets.scm
* copyright
* libs.arc: modified a tiny bit
* pprint.arc
* srv.arc
* strings.arc
* unused.tar.xz: archive of unused parts of arc

part of arc but modified by us

* html.arc
* app.arc (heavily modified)
* forum.arc (heavily modified)

new entirely

* .gitignore, README.md, run.sh
* hash.py, verify.py: tiny shim to use the python library passlib
* fb-sdk/: tiny shim to use the javascript facebook sdk
* static/miri.*

db format

* arc/admins: whitespace-separated list of admin usernames
* arc/fb_auth.json: `{"id": "...", "secret": "..."}`

#### Terminal documentation

production: `su - forum; cd ~/research-forum; ./run.sh` -> http://agentfoundations.org/

staging: `su - forum; cd ~/staging/research-forum; ./run.sh 9001` -> http://malo2-9001.terminal.com/
