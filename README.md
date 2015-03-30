#### To obtain a running instance

`./run.sh` -> <http://localhost:8080/>

for the default blank test db, login as `admin` with password `password`

#### Dependencies

mzscheme: latest version of http://racket-lang.org/ with the appropriate folder added to `$PATH`

passlib: `easy_install passlib` might work

pandoc: `brew install pandoc` might work

node v0.12

#### What are files

part of arc

* ac.scm
* arc.arc
* as.scm: `./as.scm` gives an arc repl but is otherwise unused (& modified a tiny bit)
* brackets.scm
* copyright
* libs.arc: modified a tiny bit
* pprint.arc
* strings.arc
* unused.tar.xz: archive of unused parts of arc

part of arc but modified by us

* html.arc
* srv.arc
* app.arc (heavily modified)
* forum.arc (heavily modified)

other files are new entirely.

db format

* arc/admins: whitespace-separated list of admin usernames
* arc/fb_auth.json: `{"id": "...", "secret": "..."}`

#### Terminal documentation

production: `su forum; cd ~/research-forum; ./run.sh` -> https://agentfoundations.org/
