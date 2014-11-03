To obtain a running instance:

    mkdir arc
    echo "admin" > arc/admins
    mzscheme -f as.scm

At the arc prompt:

    (load "forum.arc")
    (create-acct "admin" "password")
    (nsv)

Go to http://localhost:8080

Click on login, and login as "admin"
