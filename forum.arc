; News.  2 Sep 06.

; to run news: (nsv), then go to http://localhost:8080
; put usernames of admins, separated by whitespace, in arc/admins

; bug: somehow (+ votedir* nil) is getting evaluated.

(declare 'atstrings t)

(= this-site*    "FAI research forum"
   site-url*     "http://news.yourdomain.com/"
   parent-url*   "http://www.yourdomain.com"
   favicon-url*  ""
   site-desc*    "What this site is about."               ; for rss feed
   site-color*   (color 180 180 180)
   border-color* (color 180 180 180)
   prefer-url*   t)


; Structures

; Could add (html) types like choice, yesno to profile fields.  But not 
; as part of deftem, which is defstruct.  Need another mac on top of 
; deftem.  Should not need the type specs in user-fields.

(deftem profile
  id         nil
  name       nil
  created    (seconds)
  auth       0
  member     nil
  submitted  nil
  karma      1
  weight     .5
  email      nil
  about      nil
  keys       nil
  delay      0)

(deftem item
  id         nil
  version    0     ; incremented before first save
  draft      nil
  type       nil
  by         nil
  ip         nil
  time       nil   ; set on save
  title      nil
  text       nil
  deleted    nil
  parent     nil
  keys       nil)


; Load and Save

(= newsdir*  "arc/news/"
   storydir* "arc/news/story/"
   textdir*  "arc/news/text/"
   profdir*  "arc/news/profile/"
   votedir*  "arc/news/vote/")

(= votes* (table) profs* (table)
   itemlikes* (table) itemkids* (table) itemtext* (table))

(def nsv ((o port 8080))
  (map ensure-dir (list arcdir* newsdir* storydir* textdir* votedir* profdir*))
  (unless stories* (load-items))
  (if (empty profs*) (load-users))
  (asv port))

(def item-file (id version (o ext))
  (+ (if ext textdir* storydir*)
     id "v" version
     (if ext (+ "." ext) "")))

(def newest-item-file (id)
  (let v 1
    (while (file-exists (item-file id (+ v 1))) (++ v))
    (item-file id v)))

(def load-users ()
  (pr "load users: ")
  (noisy-each 100 id (dir profdir*)
    (load-user id)))

; For some reason vote files occasionally get written out in a 
; broken way.  The nature of the errors (random missing or extra
; chars) suggests the bug is lower-level than anything in Arc.
; Which unfortunately means all lists written to disk are probably
; vulnerable to it, since that's all save-table does.

(def load-user (u)
  (= (votes* u) (load-table (+ votedir* u))
     (profs* u) (temload 'profile (+ profdir* u)))
  (each (id dir) (tablist (votes* u))
    (when (is dir 'like) (push u (itemlikes* id))))
  u)

; Have to check goodname because some user ids come from http requests.
; So this is like safe-item.  Don't need a sep fn there though.

(def profile (u)
  (or (profs* u)
      (aand (goodname u)
            (file-exists (+ profdir* u))
            (= (profs* u) (temload 'profile it)))))

; User likes a story = (is ((votes u) i) 'like)

(def votes (u)
  (or (votes* u)
      (aand (file-exists (+ votedir* u))
            (= (votes* u) (load-table it)))))

(def vote (user item)
  (votes.user item!id))

(def init-user (u)
  (= (votes* u) (table) 
     (profs* u) (inst 'profile 'id u))
  (save-votes u)
  (save-prof u)
  u)

; Need this because can create users on the server (for other apps)
; without setting up places to store their state as news users.
; See the admin op in app.arc.  So all calls to login-page from the 
; news app need to call this in the after-login fn.

(def ensure-news-user (u)
  (if (profile u) u (init-user u)))

(def save-votes (u) (save-table (votes* u) (+ votedir* u)))

(def save-prof  (u) (save-table (profs* u) (+ profdir* u)))

(mac uvar (u k) `((profile ,u) ',k))

(mac karma   (u) `(uvar ,u karma))

; Note that users will now only consider currently loaded users.

(def users ((o f idfn)) 
  (keep f (keys profs*)))

(def check-key (u k)
  (and u (mem k (uvar u keys))))

(def author (u i) (is u i!by))

(def item-text (i) (itemtext* i!id))


(= stories* nil comments* nil 
   items* (table) maxid* 0 initload* 15000)

; The dir expression yields stories in order of file creation time 
; (because arc infile truncates), so could just rev the list instead of
; sorting, but sort anyway.

; Note that stories* etc only include the initloaded (i.e. recent)
; ones, plus those created since this server process started.

; Could be smarter about preloading by keeping track of popular pages.

(def load-items ()
  (system (+ "rm " storydir* "*.tmp"))
  (pr "load items: ")
  (with (items (table)
         ids  (sort > (map [int:car:tokens _ #\v] (dir storydir*))))
    (if ids (= maxid* (car ids)))
    (noisy-each 100 id (firstn initload* ids)
      (when (~items* id)
        (let i (load-item id)
          (push i (items i!type)))))
    (= stories*  (rev items!story)
       comments* (rev items!comment))
    (hook 'initload items))
  (ensure-topstories))

(def ensure-topstories ()
  (aif (errsafe (readfile1 (+ newsdir* "topstories")))
       (= ranked-stories* (map item it))
       (do (prn "ranking stories.") 
           (flushout)
           (gen-topstories))))

(def astory   (i) (and i (is i!type 'story)))
(def acomment (i) (and i (is i!type 'comment)))

(def load-item (id)
  (let i (temload 'item (newest-item-file id))
    (= (itemtext* id) (filechars:item-file id i!version "html"))
    (if i!parent (pushnew id (itemkids* i!parent)))
    (= (items* id) i)))

(def new-item-id ()
  (evtil (++ maxid*) [~file-exists (+ storydir* _ "v1")]))

(def item (id)
  (or (items* id) (errsafe:load-item id)))

(def kids (i) (map item (itemkids* i!id)))

; For use on external item references (from urls).  Checks id is int 
; because people try e.g. item?id=363/blank.php

(def safe-item (id)
  (ok-id&item (if (isa id 'string) (saferead id) id)))

(def ok-id (id) 
  (and (exact id) (<= 1 id maxid*)))

(def arg->item (req key)
  (safe-item:saferead (arg req key)))

(def live (i) (no i!deleted))

(def save-item (i)
  (++ i!version)
  (= i!time (seconds))
  (w/outfile f (item-file i!id i!version "md") (disp i!text f))
  (system (+ "pandoc --mathjax -S -f markdown-raw_html "
             (item-file i!id i!version "md")
             " -o "
             (item-file i!id i!version "html")))
  (= (itemtext* i!id) (filechars (item-file i!id i!version "html")))
  (save-table i (item-file i!id i!version)))

(mac each-loaded-item (var . body)
  (w/uniq g
    `(let ,g nil
       (loop (= ,g maxid*) (> ,g 0) (-- ,g)
         (whenlet ,var (items* ,g)
           ,@body)))))

(def loaded-items (test)
  (accum a (each-loaded-item i (test&a i))))

(def newslog args (apply srvlog 'news args))


; Ranking

; Votes divided by the age in hours to the gravityth power.
; Would be interesting to scale gravity in a slider.

(= gravity* 1.8 timebase* 120 front-threshold* 1)

(def frontpage-rank (s (o scorefn realscore) (o gravity gravity*))
  (* (/ (let base (- (scorefn s) 1)
          (if (> base 0) (expt base .8) base))
        (expt (/ (+ (item-age s) timebase*) 60) gravity))
     (if (~astory s)  .5
                      (contro-factor s))))

(def contro-factor (s)
  (aif (check (visible-family nil s) [> _ 20])
       (min 1 (expt (/ (realscore s) it) 2))
       1))

(def realscore (i) (+ 1 (len (itemlikes* i!id))))

(def item-age (i) (minutes-since i!time))

(def user-age (u) (minutes-since (uvar u created)))

(def gen-topstories ()
  (= ranked-stories* (rank-stories 180 1000 (memo frontpage-rank))))

(def save-topstories ()
  (writefile (map !id (firstn 180 ranked-stories*))
             (+ newsdir* "topstories")))
 
(def rank-stories (n consider scorefn)
  (bestn n (compare > scorefn) (latest-items astory nil consider)))

; With virtual lists the above call to latest-items could be simply:
; (map item (retrieve consider astory:item (gen maxid* [- _ 1])))

(def latest-items (test (o stop) (o n))
  (accum a
    (catch 
      (down id maxid* 1
        (let i (item id)
          (if (or (and stop (stop i)) (and n (<= n 0))) 
              (throw))
          (when (test i) 
            (a i) 
            (if n (-- n))))))))

(def adjust-rank (s (o scorefn frontpage-rank))
  (insortnew (compare > (memo scorefn)) s ranked-stories*)
  (save-topstories))

; If something rose high then stopped getting votes, its score would
; decline but it would stay near the top.  Newly inserted stories would
; thus get stuck in front of it. I avoid this by regularly adjusting 
; the rank of a random top story.

(defbg rerank-random 30 (rerank-random))

(def rerank-random ()
  (when ranked-stories*
    (adjust-rank (ranked-stories* (rand (min 50 (len ranked-stories*)))))))

(def topstories (user n (o threshold front-threshold*))
  (retrieve n 
            [and (>= (realscore _) threshold) (cansee user _)]
            ranked-stories*))

(= max-delay* 10)

(def cansee (user i)
  (if i!deleted   (admin user)
      i!draft     (author user i)
      (delayed i) (author user i)
      t))

(let mature (table)
  (def delayed (i)
    (and (no (mature i!id))
         (acomment i)
         (or (< (item-age i) (min max-delay* (uvar i!by delay)))
             (do (set (mature i!id))
                 nil)))))

(def visible (user is)
  (keep [cansee user _] is))

(def cansee-descendant (user c)
  (or (cansee user c)
      (some [cansee-descendant user _] (kids c))))
  
(def editor (u) 
  (and u (or (admin u) (> (uvar u auth) 0))))

(def member (u) 
  (and u (or (admin u) (uvar u member))))


; Page Layout

(= logo-url* "arc.png")

(defopr favicon.ico req favicon-url*)

; redefined later

(def gen-css-url ()
  (prn "<link rel=\"stylesheet\" type=\"text/css\" href=\"forum.css\">"))

(mac npage (title . body)
  `(tag html 
     (tag head 
       (gen-css-url)
       (prn "<link rel=\"shortcut icon\" href=\"" favicon-url* "\">")
       (prn "<script src=\"https://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML\" type=\"text/javascript\"></script>")
       (tag title (pr ,title)))
     (tag body 
       (center
         (tag (table border 0 cellpadding 0 cellspacing 0 width "85%"
                     bgcolor sand)
           ,@body)))))

(= pagefns* nil)

(mac fulltop (user lid label title whence . body)
  (w/uniq (gu gi gl gt gw)
    `(with (,gu ,user ,gi ,lid ,gl ,label ,gt ,title ,gw ,whence)
       (npage (+ this-site* (if ,gt (+ bar* ,gt) ""))
         (do (pagetop 'full ,gi ,gl ,gt ,gu ,gw)
             (hook 'page ,gu ,gl)
             ,@body)))))

(mac longpage (user t1 lid label title whence . body)
  (w/uniq (gu gt gi)
    `(with (,gu ,user ,gt ,t1 ,gi ,lid)
       (fulltop ,gu ,gi ,label ,title ,whence
         (trtd ,@body)
         (trtd (vspace 10)
               (color-stripe site-color*)
               (br)
               (center
                 (hook 'longfoot)
                 (admin-bar ,gu (- (msec) ,gt) ,whence)))))))

(mac add-sidebar (title contents . body)
  `(tag (table style 'border-collapse:collapse width '100%)
        (tr (tag (td valign 'top class 'contents) ,@body)
            (tag (td valign 'top class 'csb)
              (para (tag (h3) (pr ,title))) ,contents))))

(mac longpage-csb (user t1 lid label title whence show-comments . body)
  `(longpage ,user ,t1 ,lid ,label ,title ,whence
     (if (no ,show-comments) 
       (do ,@body)
       (add-sidebar (link "RECENT COMMENTS" "newcomments")
                    (each c (csb-items ,user csb-count*)
                      (tag (p) (tag (a href (item-url c!id) class 'csb)
                                 (tag (b) (pr (shortened c!text csb-maxlen*))))
                               (br)
                               (tab (tr (tag (td class 'csb-subtext)
                                 (pr "by ")
                                 (userlink user c!by)
                                 (pr " on ")
                                 (let s (superparent c) 
                                   (pr (ellipsize s!title 50)))
                                 (pr bar*)
                                 (itemscore c))))))
         ,@body))))

(def reverse (text)
  (coerce (rev (coerce text 'cons)) 'string))

(def word-boundary (text)
  (if (is (len (halve text)) 1) text
    (reverse ((halve (reverse text)) 1))))

(def shortened (text maxlen)
  (if (<= (len text) maxlen) text
    (word-boundary (cut text 0 maxlen))))

(def admin-bar (user elapsed whence)
  (when (admin user)
    (br2)
    (w/bars
      (pr (len items*) "/" maxid* " loaded")
      (pr (round (/ (memory) 1000000)) " mb")
      (pr elapsed " msec")
      (link "settings" "newsadmin")
      (hook 'admin-bar user whence))))

(def color-stripe (c)
  (tag (table width "100%" cellspacing 0 cellpadding 1)
    (tr (tdcolor c))))

(mac shortpage (user lid label title whence . body)
  `(fulltop ,user ,lid ,label ,title ,whence 
     (trtd ,@body)))

(mac minipage (label . body)
  `(npage (+ this-site* bar* ,label)
     (pagetop nil nil ,label)
     (trtd ,@body)))

(def msgpage (user msg (o title))
  (minipage (or title "Message")
    (spanclass admin
      (center (if (len> msg 80) 
                  (widtable 500 msg)
                  (pr msg))))
    (br2)))

(= (max-age* 'forum.css) 86400)   ; cache css in browser for 1 day

; turn off server caching via (= caching* 0) or won't see changes
(= caching* 0)

(defop forum.css req
  (pr "
body  { font-family:Verdana; font-size:13pt; color:#828282; }
td    { font-family:Verdana; font-size:13pt; color:#000000; }

hr       { border:0; text-align:center; }
hr:after { content:\"*\"; }

td > h1 { font-family:Verdana; font-size:14pt; color:#000000; font-weight:bold; }

table td.csb      { background-color:#e6e6e6; width:300px; padding:8px; font-size:10pt; }
table td.csb > h3 { font-family:Verdana; font-size:12pt; font-weight:bold; }
table td.contents { margin:0; padding-right:80; }
table td.story    { line-height:135%; }

.admin td   { font-family:Verdana; font-size:10.5pt; color:#000000; }
.subtext td { font-family:Verdana; font-size:  10pt; color:#828282; }

button   { font-family:Verdana; font-size:11pt; color:#000000; }
input    { font-family:Courier; font-size:13pt; color:#000000; }
input[type=\"submit\"] { font-family:Verdana; }
textarea { font-family:Courier; font-size:13pt; color:#000000; }

a:link    { color:#000000; text-decoration:none; } 
a:visited { color:#555555; text-decoration:none; }

.default     { font-family:Verdana; font-size:  13pt; color:#828282; }
.admin       { font-family:Verdana; font-size:10.5pt; color:#000000; }
.title       { font-family:Verdana; font-size:  16pt; color:#828282; font-weight:bold; }
.adtitle     { font-family:Verdana; font-size:  11pt; color:#828282; }
.subtext     { font-family:Verdana; font-size:  10pt; color:#828282; }
.csb-subtext { font-family:Verdana; font-size:   8pt; color:#828282; }
.yclinks     { font-family:Verdana; font-size:  10pt; color:#828282; }
.pagetop     { font-family:Verdana; font-size:  13pt; color:#222222; }
.comhead     { font-family:Verdana; font-size:  10pt; color:#828282; }
.comment     { font-family:Verdana; font-size:  13pt; }
.dead        { font-family:Verdana; font-size:  11pt; color:#dddddd; }

.userlink, .you { font-weight:bold; }

.comment a:link, .comment a:visited, .story a:link, .story a:visited { text-decoration:underline; }
.dead a:link, .dead a:visited { color:#dddddd; }
.pagetop a:visited { color:#000000;}
.topsel a:link, .topsel a:visited { color:#ffffff; }

.subtext a:link, .subtext a:visited { color:#828282; }
.subtext a:hover { text-decoration:underline; }

.csb a:link, .csb a:visited { color:#828282; }
.csb a:hover { text-decoration:underline; }

.comhead a:link, .subtext a:visited { color:#828282; }
.comhead a:hover { text-decoration:underline; }

.continue a:link, .subtext a:visited { color:#828282; text-decoration:underline; }

.default p { margin-top: 8px; margin-bottom: 0px; }

.pagebreak {page-break-before:always}

pre { overflow: auto; padding: 2px; max-width:600px; }
pre:hover {overflow:auto} "))

; only need pre padding because of a bug in Mac Firefox

; Without setting the bottom margin of p tags to 0, 1- and n-para comments
; have different space at the bottom.  This solution suggested by Devin.
; Really am using p tags wrong (as separators rather than wrappers) and the
; correct thing to do would be to wrap each para in <p></p>.  Then whatever
; I set the bottom spacing to, it would be the same no matter how many paras
; in a comment. In this case by setting the bottom spacing of p to 0, I'm
; making it the same as no p, which is what the first para has.

; supplied by pb
;.vote { padding-left:2px; vertical-align:top; }
;.comment { margin-top:1ex; margin-bottom:1ex; color:black; }
;.vote IMG { border:0; margin: 3px 2px 3px 2px; }
;.reply { font-size:smaller; text-decoration:underline !important; }


; Page top

(= sand (color 246 246 239) textgray (gray 130))

(def pagetop (switch lid label (o title) (o user) (o whence))
; (tr (tdcolor black (vspace 5)))
  (tr (tdcolor site-color*
        (tag (table border 0 cellpadding 0 cellspacing 0 width "100%"
                    style "padding:2px")
          (tr (gen-logo)
              (when (is switch 'full)
                (tag (td style "line-height:12pt; height:10px;")
                  (spanclass pagetop
                    (tag b (link this-site* "news"))
                    (hspace 10)
                    (toprow user label))))
             (if (is switch 'full)
                 (tag (td style "text-align:right;padding-right:4px;")
                   (spanclass pagetop (topright user whence)))
                 (tag (td style "line-height:12pt; height:10px;")
                   (spanclass pagetop (prbold label))))))))
  (map [_ user] pagefns*)
  (spacerow 10))

(def gen-logo ()
  (tag (td style "width:18px;padding-right:4px")
    (tag (a href parent-url*)
      (tag (img src logo-url* width 18 height 18 
                style "border:1px #@(hexrep border-color*) solid;")))))

(= toplabels* '(nil "new" "comments" "members" 
                    "my posts" "my comments" "my likes" "*"))

; redefined later

(def toprow (user label)
  (w/bars 
    (toplink "new" "newest" label)
    (toplink "comments" "newcomments" label)
    (toplink "members"  "members"     label)
    (when user
      (w/bars
        (toplink "my posts" (submitted-url user) label)
        (toplink "my comments" (threads-url user) label)
        (toplink "my likes" (saved-url user) label)))
    (hook 'toprow user label)
    (link "submit")
    (unless (mem label toplabels*)
      (fontcolor white (pr label)))))

(def toplink (name dest label)
  (tag-if (is name label) (span class 'topsel)
    (link name dest)))

(def topright (user whence (o showkarma t))
  (when user 
    (userlink user user)
    (when showkarma (pr  "&nbsp;(@(* karma-multiplier* (karma user)))"))
    (pr "&nbsp;|&nbsp;"))
  (if user
      (rlinkf 'logout (req)
        (when-umatch/r user req
          (logout-user user)
          whence))
      (onlink "login"
        (login-page 'login nil
                    (list (fn (u ip) 
                            (ensure-news-user u)
                            (newslog ip u 'top-login))
                          whence)))))


; News-Specific Defop Variants

(mac defopt (name parm test msg . body)
  `(defop ,name ,parm
     (if (,test (get-user ,parm))
         (do ,@body)
         (login-page 'login (+ "Please log in" ,msg ".")
                     (list (fn (u ip) (ensure-news-user u))
                           (string ',name (reassemble-args ,parm)))))))

(mac defopg (name parm . body)
  `(defopt ,name ,parm idfn "" ,@body))

(mac defope (name parm . body)
  `(defopt ,name ,parm editor " as an editor" ,@body))

(mac defopa (name parm . body)
  `(defopt ,name ,parm admin " as an administrator" ,@body))

(mac opexpand (definer name parms . body)
  (w/uniq gr
    `(,definer ,name ,gr
       (with (user (get-user ,gr) ip (,gr 'ip))
         (with ,(and parms (mappend [list _ (list 'arg gr (string _))]
                                    parms))
           (newslog ip user ',name ,@parms)
           ,@body)))))

(= newsop-names* nil)

(mac newsop args
  `(do (pushnew ',(car args) newsop-names*)
       (opexpand defop ,@args)))

(mac adop (name parms . body)
  (w/uniq g
    `(opexpand defopa ,name ,parms 
       (let ,g (string ',name)
         (shortpage user nil ,g ,g ,g
           ,@body)))))

(mac edop (name parms . body)
  (w/uniq g
    `(opexpand defope ,name ,parms 
       (let ,g (string ',name)
         (shortpage user nil ,g ,g ,g
           ,@body)))))


; News Admin

(defopa newsadmin req 
  (let user (get-user req)
    (newslog req!ip user 'newsadmin)
    (newsadmin-page user)))

; Note that caching* is reset to val in source when restart server.

(def nad-fields ()
  `((num      caching         ,caching*                       t t)))

; Need a util like vars-form for a collection of variables.
; Or could generalize vars-form to think of places (in the setf sense).

(def newsadmin-page (user)
  (shortpage user nil nil "newsadmin" "newsadmin"
    (para (onlink "Create Account" (admin-page user)))
    (vars-form user 
               (nad-fields)
               (fn (name val)
                 (case name
                   caching            (= caching* val)
                   ))
               (fn () (newsadmin-page user)))))


; Users

(newsop user (id)
  (if (only.profile id)
      (user-page user id)
      (pr "No such user.")))

(def user-page (user subject)
  (let here (user-url subject)
    (shortpage user nil nil (+ "Profile: " subject) here
      (profile-form user subject)
      (br2)
      (when (some astory:item (uvar subject submitted))
        (underlink "posts" (submitted-url subject)))
      (when (some acomment:item (uvar subject submitted))
        (sp)
        (underlink "comments" (threads-url subject)))
      (pr " " (saved-link user subject))
      (hook 'user user subject))))

(def profile-form (user subject)
  (let prof (profile subject) 
    (vars-form user
               (user-fields user subject)
               (fn (name val) 
                 (= (prof name) val))
               (fn () (save-prof subject)
                      (user-page user subject)))))

(def user-fields (user subject)
  (withs (e (editor user) 
          a (admin user) 
          w (is user subject)
          u (or a w)
          m (or a (and (member user) w))
          p (profile subject))
    `((string  user       ,subject                                  t   nil)
      (string  name       ,(p 'name)                               ,m  ,m)
      (string  created    ,(text-age:user-age subject)              t   nil)
      (string  password   ,(resetpw-link)                          ,w   nil)
      (string  saved      ,(saved-link user subject)               ,u   nil)
      (int     auth       ,(p 'auth)                               ,e  ,a)
      (yesno   member     ,(p 'member)                             ,a  ,a)
      (posint  karma      ,(p 'karma)                               t  ,a)
      (num     weight     ,(p 'weight)                             ,a  ,a)
      (mdtext  about      ,(p 'about)                               t  ,u)
      (string  email      ,(p 'email)                              ,u  ,u)
      (sexpr   keys       ,(p 'keys)                               ,a  ,a)
      (int     delay      ,(p 'delay)                              ,u  ,u))))

(def saved-link (user subject)
  (let n (if (len> (votes subject) 500) 
             "many" 
             (len (liked-stories user subject)))
    (tostring (underlink (+ (string n) " liked " (if (is n 1) "story" "stories"))
                         (saved-url subject)))))

(def resetpw-link ()
  (tostring (underlink "reset password" "resetpw")))


; Main Operators

; remember to set caching to 0 when testing non-logged-in 

(= caching* 1 perpage* 25 threads-perpage* 10 maxend* 500
   csb-count* 5 csb-maxlen* 30 preview-maxlen* 1000
   karma-multiplier* 5)

; Limiting that newscache can't take any arguments except the user.
; To allow other arguments, would have to turn the cache from a single 
; stored value to a hash table whose keys were lists of arguments.

(mac newscache (name user time . body)
  (w/uniq gc
    `(let ,gc (cache (fn () (* caching* ,time))
                     (fn () (tostring (let ,user nil ,@body))))
       (def ,name (,user) 
         (if ,user 
             (do ,@body) 
             (pr (,gc)))))))


(newsop news () (newspage user))

(newsop ||   () (newspage user))

;(newsop index.html () (newspage user))

(def csb-items (user n) (retrieve n [cansee user _] comments*))

(def newspage (user) (newestpage user))

(def listpage (user t1 items label title 
               (o url label) (o number t) (o show-comments t) (o preview-only t) (o show-immediate-parent))
  (hook 'listpage user)
  (longpage-csb user t1 nil label title url show-comments
    (display-items user items label title url 0 perpage* number preview-only show-immediate-parent)))


(newsop newest () (newestpage user))

; Note: deleted items will persist for the remaining life of the 
; cached page.  If this were a prob, could make deletion clear caches.

(newscache newestpage user 40
  (listpage user (msec) (newstories user maxend*) "new" "New Links" "newest" 
            nil t))

(def newstories (user n)
  (retrieve n [cansee user _] stories*))


(newsop best () (bestpage user))

(newscache bestpage user 1000
  (listpage user (msec) (beststories user maxend*) "best" "Top Links"))

; As no of stories gets huge, could test visibility in fn sent to best.

(def beststories (user n)
  (bestn n (compare > realscore) (visible user stories*)))


(newsop bestcomments () (bestcpage user))

(newscache bestcpage user 1000
  (listpage user (msec) (bestcomments user maxend*) 
            "best comments" "Best Comments" "bestcomments" nil))

(def bestcomments (user n)
  (bestn n (compare > realscore) (visible user comments*)))


(newsop lists () 
  (longpage-csb user (msec) nil "lists" "Lists" "lists" t
    (sptab
      (row (link "best")         "Highest voted recent links.")
      (row (link "active")       "Most active current discussions.")
      (row (link "bestcomments") "Highest voted recent comments.")
      (when (admin user)
        (row (link "optimes")))
      (hook 'listspage user))))


(def saved-url (user) (+ "saved?id=" user))

(newsop saved (id) 
  (if (only.profile id)
      (savedpage user id) 
      (pr "No such user.")))

(def savedpage (user subject)
  (withs (title (+ subject "'s likes")
          label (if (is user subject) "my likes" title)
          here  (saved-url subject))
    (listpage user (msec)
              (sort (compare < item-age) (liked-stories user subject)) 
              label title here)))

(def liked-stories (user subject)
  (keep [and (astory _) (cansee user _) (is ((votes subject) _!id) 'like)]
        (map item (keys:votes subject))))


; Story Display

(def display-items (user items label title whence 
                    (o start 0) (o end perpage*) (o number) (o preview-only) (o show-immediate-parent))
  (tag (table width '100%)
    (let n start
      (each i (cut items start end)
        (trtd (tag (table width '100%) (display-item (and number (++ n)) i user whence t preview-only show-immediate-parent)
             (spacerow (if (acomment i) 15 30))))))
    (when end
      (let newend (+ end perpage*)
        (when (and (<= newend maxend*) (< end (len items)))
          (spacerow 10)
          (tr (tag (td colspan (if number 2 1)))
              (td
                (morelink display-items 
                          items label title end newend number))))))))

; This code is inevitably complex because the More fn needs to know 
; its own fnid in order to supply a correct whence arg to stuff on 
; the page it generates, like logout and delete links.

(def morelink (f items label title . args)
  (tag (a href 
          (url-for
            (afnid (fn (req)
                     (prn)
                     (with (url  (url-for it)     ; it bound by afnid
                            user (get-user req))
                       (newslog req!ip user 'more label)
                       (longpage-csb user (msec) nil label title url t
                         (apply f user items label title url args))))))
          rel 'nofollow)
    (pr "More")))

(def display-story (i s user whence preview-only (o commentpage))
  (when (or (cansee user s) (itemkids* s!id))
    (tr (when (no commentpage)
          (td (votelinks-space))
          (display-item-number i))
        (titleline s user whence))
    (tr (when (no commentpage)
          (tag (td colspan (if i 2 1))))
        (tag (td class 'subtext)
          (hook 'itemline s user)
          (itemline s user whence)
          (when (astory s) (commentlink s user))
          (editlink s user)
          (deletelink s user whence)))
    (spacerow 10)
    (tr (when (no commentpage)
          (tag (td colspan (if i 2 1))))
        (tag (td class 'story width '100%)
          (let displayed (display-item-text s user preview-only)
            (pr displayed)
            (if (and preview-only (no (is displayed (item-text s))))
              (tag (table width '100%)
                (spacerow 20)
                (tr (tag (td align 'right class 'continue)
                  (link "continue reading &raquo;" (item-url s!id)))))))))))

(def display-item-number (i)
  (when i (tag (td align 'right valign 'top class 'title)
            (pr i "."))))

(def titleline (s user whence)
  (tag (td class 'title)
    (if (cansee user s)
        (do (deadmark s user)
            (link s!title (item-url s!id)))
        (pr "[deleted]"))))

(def deadmark (i user)
  (when (and i!deleted (admin user))
    (pr " [deleted] ")))

; TODO: the following function used to be the one generating the voting arrows;
; this function should be removed instead of existing but
; only producing whitespace
(def votelinks-space ()
  (hspace 14))

(def vote-url (user i dir whence)
  (+ "vote?" "for=" i!id
             "&dir=" dir
             (if user (+ "&by=" user "&auth=" (user->cookie* user)))
             "&whence=" (urlencode whence)))

; Further tests applied in vote-for.

(def canvote (user i dir)
  (and user
       (news-type&live i)
       (~author user i)
       (in dir 'like nil)
       (isnt dir (vote user i))))

; Need the by argument or someone could trick logged in users into 
; voting something up by clicking on a link.  But a bad guy doesn't 
; know how to generate an auth arg that matches each user's cookie.

(newsop vote (by for dir auth whence)
  (with (i      (safe-item for)
         dir    (saferead dir)
         whence (if whence (urldecode whence) "news"))
    (if (no i)
         (pr "No such item.")
        (no (in dir 'like nil))
         (pr "Can't make that vote.")
        (is dir (vote user i))
         (pr "Already voted that way.")
        (and by (or (isnt by user) (isnt (sym auth) (user->cookie* user))))
         (pr "User mismatch.")
        (no user)
         (login-page 'login "You have to be logged in to vote."
                     (list (fn (u ip)
                             (ensure-news-user u)
                             (newslog ip u 'vote-login)
                             (when (canvote u i dir)
                               (vote-for u i dir)
                               (logvote ip u i dir)))
                           whence))
        (canvote user i dir)
         (do (vote-for by i dir)
             (logvote ip by i dir)
             (pr "<meta http-equiv='refresh' content='0; url="
                 (esc-tags whence) "' />"))
         (pr "Can't make that vote."))))

(mac and-list (render items ifempty . body)
  `(with (items ,items)
     (if (no items) ,ifempty
       (let it (fn () (do (on i items
                            (,render i)
                            (if (< index (- (len items) 2))
                                 (pr ", ")
                                (is index (- (len items) 2))
                                 (pr " and ")))))
         ,@body))))

(def itemline (i user whence)
  (when (cansee user i) 
    (byline i user)
    (and-list [userlink-or-you user _] (likes i user) (pr)
              (pr bar*) (it) (pr " like" (if (or (iso items (list user))
                                                 (cdr items))
                                             "" "s")
                                 " this"))
    (when (canvote user i 'like)
      (pr bar*)
      (clink likelink "Like" (vote-url user i 'like whence)))
    (when (canvote user i nil)
      (pr bar*)
      (clink likelink "Unlike" (vote-url user i nil whence)))))

(def likes (i user)
  (+ (if (mem user (itemlikes* i!id)) (list user) '())
     (sort < (rem user (itemlikes* i!id)))))

(def itemscore (i (o user))
  (tag (span id (+ "score_" i!id))
    (pr (plural (len (likes i user)) "like")))
  (hook 'itemscore i user))

(def byline (i user)
  (pr " by @(tostring (userlink user i!by)) @(text-age:item-age i) "))

(def user-url (user) (+ "user?id=" user))

(def userlink (user subject)
  (clink userlink subject (user-url subject)))

(def userlink-or-you (user subject)
  (if (is user subject) (spanclass you (pr "You")) (userlink user subject)))

(def commentlink (i user)
  (when (cansee user i) 
    (pr bar*)
    (tag (a href (item-url i!id))
      (let n (- (visible-family user i) 1)
        (if (> n 0)
            (pr (plural n "comment"))
            (pr "discuss"))))))

(def visible-family (user i)
  (+ (if (cansee user i) 1 0)
     (sum [visible-family user (item _)] (itemkids* i!id))))

;(= user-changetime* 120 editor-changetime* 1440)

(= everchange* (table) noedit* (table))

(def canedit (user i)
  (or (admin user)
      (and (~noedit* i!type)
           (editor user))
           ;(< (item-age i) editor-changetime*))
      (own-changeable-item user i)))

(def own-changeable-item (user i)
  (and (author user i)
       (~mem 'locked i!keys)
       (no i!deleted)))
       ;(or (everchange* i!type)
       ;    (< (item-age i) user-changetime*))))

(def editlink (i user)
  (when (canedit user i)
    (pr bar*)
    (link "edit" (edit-url i))))


(def candelete (user i)
  (or (admin user) (own-changeable-item user i)))

(def deletelink (i user whence)
  (when (candelete user i)
    (pr bar*)
    (linkf (if i!deleted "undelete" "delete") (req)
      (let user (get-user req)
        (if (candelete user i)
            (del-confirm-page user i whence)
            (prn "You can't delete that."))))))

(def del-confirm-page (user i whence)
  (minipage "Confirm"
    (tab 
      ; link never used so not testable but think correct
      (display-item nil i user (flink [del-confirm-page (get-user _) i whence]))
      (spacerow 20)
      (tr (td)
          (td (urform user req
                      (do (when (candelete user i)
                            (= i!deleted (is (arg req "b") "Yes"))
                            (save-item i))
                          whence)
                 (prn "Do you want this to @(if i!deleted 'stay 'be) deleted?")
                 (br2)
                 (but "Yes" "b") (sp) (but "No" "b")))))))

(def permalink (story user)
  (when (cansee user story)
    (pr bar*) 
    (link "link" (item-url story!id))))

(def logvote (ip user story dir)
  (newslog ip user 'vote story!id dir (list (story 'title))))

(def text-age (a)
  (tostring
    (if (>= a 1440) (pr (plural (trunc (/ a 1440)) "day")    " ago")
        (>= a   60) (pr (plural (trunc (/ a 60))   "hour")   " ago")
                    (pr (plural (trunc a)          "minute") " ago"))))


; Voting

(def vote-for (user i (o dir 'like))
  (unless (or (is (vote user i) dir)
              (author user i)
              (~live i))
    (astory&adjust-rank i)
    (++ (karma i!by) (case dir like 1 nil -1))
    (save-prof i!by)
    (wipe (comment-cache* i!id))
    (if (is dir 'like) (pushnew user (itemlikes* i!id))
                       (zap [rem user _] (itemlikes* i!id)))
    (= ((votes* user) i!id) dir)
    (save-votes user)))


; Story Submission

(newsop submit ()
  (if user 
      (submit-page user "" t) 
      (submit-login-warning "" t)))

(def submit-login-warning ((o title) (o showtext) (o text))
  (login-page 'login "You have to be logged in to submit."
              (fn (user ip) 
                (ensure-news-user user)
                (newslog ip user 'submit-login)
                (submit-page user title showtext text))))

(def submit-page (user (o title) (o showtext) (o text "") (o msg))
  (shortpage user nil nil "Submit" "submit"
    (pagemessage msg)
    (urform user req
            (process-story (get-user req)
                           (striptags (arg req "t"))
                           showtext
                           (and showtext (arg req "x"))
                           req!ip
                           (no (is (arg req "draft") nil)))
      (tab
        (row "title"  (input "t" title 50))
        (tr
          (td "text")
          (td 
            (textarea "x" 4 50 (only.pr text))
            (pr " ")
            (tag (font size -2)
              (tag (a href formatdoc-url* target '_blank)
                (tag (font color (gray 175)) (pr "formatting help"))))))
        (row "" (do
                  (tag (button type 'submit
                               name "draft"
                               value "t"
                               onclick "needToConfirm = false;")
                    (pr "save draft & preview"))
                  (protected-submit "publish post")))))))

; For use by outside code like bookmarklet.
; http://news.domain.com/submitlink?u=http://foo.com&t=Foo
; Added a confirm step to avoid xss hacks.

(newsop submitlink (u t)
  (if user 
      (submit-page user u t)
      (submit-login-warning u t)))

(= title-limit* 160
   retry*       "Please try again."
   toolong*     "Please make title < @title-limit* characters."
   blanktext*   "Please fill in the title and the body.")

(def process-story (user title showtext text ip draft)
  (if (no user)
       (flink [submit-login-warning title showtext text])
      (or (blank title) (blank text))
       (flink [submit-page user title showtext text blanktext*])
      (len> title title-limit*)
       (flink [submit-page user title showtext text toolong*])
      (let s (create-story title text user ip draft)
        (submit-item user s)
        "newest")))

(def submit-item (user i)
  (push i!id (uvar user submitted))
  (save-prof user)
  (astory&adjust-rank i))

(def create-story (title text user ip draft)
  (newslog ip user 'create (list title))
  (let s (inst 'item 'type 'story 'id (new-item-id) 
                     'title title 'text text 'by user 'ip ip 'draft draft)
    (save-item s)
    (= (items* s!id) s)
    (push s stories*)
    s))


; Individual Item Page (= Comments Page of Stories)

(defmemo item-url (id) (+ "item?id=" id))

(newsop item (id)
  (let s (safe-item id)
    (if (news-type s)
        (do (if s!deleted (note-baditem user ip))
            (item-page user s))
        (do (note-baditem user ip)
            (pr "No such item.")))))

(= baditemreqs* (table) baditem-threshold* 1/100)

; Something looking at a lot of deleted items is probably the bad sort
; of crawler.  Throttle it for this server invocation.

(def note-baditem (user ip)
  (unless (admin user)
    (++ (baditemreqs* ip 0))
    (with (r (requests/ip* ip) b (baditemreqs* ip))
       (when (and (> r 500) (> (/ b r) baditem-threshold*))
         (set (throttle-ips* ip))))))

; redefined later

(def news-type (i) (and i (in i!type 'story 'comment)))

(def item-page (user i)
  (with (title (and (cansee user i)
                    (or i!title (aand (item-text i) 
                                      (ellipsize (striptags it)))))
         here (item-url i!id))
    (longpage-csb user (msec) nil nil title here t
      (tab (display-item nil i user here)
           (when (and (cansee user i) (comments-active i))
             (spacerow 10)
             (row "" (comment-form i user here))))
      (br2) 
      (when (and (itemkids* i!id) (commentable i))
        (tab (display-subcomments i user here))
        (br2)))))

(def commentable (i) (in i!type 'story 'comment))

; By default the ability to comment on an item is turned off after 
; 45 days, but this can be overriden with commentable key.

(= commentable-threshold* (* 60 24 45))

(def comments-active (i)
  (and (live&commentable i)
       (live (superparent i))
       (or (< (item-age i) commentable-threshold*)
           (mem 'commentable i!keys))))


(= displayfn* (table))

(= (displayfn* 'story)   (fn (n i user here inlist preview-only show-immediate-parent)
                           (display-story n i user here preview-only)))

(= (displayfn* 'comment) (fn (n i user here inlist preview-only show-immediate-parent)
                           (display-comment n i user here nil 0 nil inlist show-immediate-parent)))

(def display-item (n i user here (o inlist) (o preview-only) (o show-immediate-parent))
  ((displayfn* (i 'type)) n i user here inlist preview-only show-immediate-parent))

(def superparent (i)
  (aif i!parent (superparent:item it) i))

(def until-token (text token)
  (let index (posmatch token text)
    (if (no index) text
      (cut text 0 index))))

(def preview (text)
  (withs (idx-hr (posmatch "<hr" text) idx-h1 (posmatch "<h1" text))
    (if
      (and idx-hr idx-h1) (if
                            (< idx-hr idx-h1) (until-token text "<hr")
                            (until-token text "<h1"))
      idx-hr (until-token text "<hr")
      idx-h1 (until-token text "<h1")
      (<= (len text) preview-maxlen*) text
      (+ (until-token text "</p>") "</p>"))))

(def display-item-text (s user preview-only)
  (when (and (cansee user s) (astory s))
    (if preview-only (preview (item-text s)) (item-text s))))


; Edit Item

(def edit-url (i) (+ "edit?id=" i!id))

(newsop edit (id)
  (let i (safe-item id)
    (if (and i 
             (cansee user i)
             (editable-type i)
             (or (news-type i) (admin user) (author user i)))
        (edit-page user i)
        (pr "No such item."))))

(def editable-type (i) (fieldfn* i!type))

(= fieldfn* (table))

(= (fieldfn* 'story)
   (fn (user s)
     (with (a (admin user)  e (editor user)  x (canedit user s))
       `((string2 title     ,s!title        t ,x)
         (pandoc  text      ,s!text         t ,x)
         ,@(standard-item-fields s a e x)))))

(= (fieldfn* 'comment)
   (fn (user c)
     (with (a (admin user)  e (editor user)  x (canedit user c))
       `((pandoc  text      ,c!text         t ,x)
         ,@(standard-item-fields c a e x)))))

(def standard-item-fields (i a e x)
  (let fields `((int     likes     ,(len (itemlikes* i!id)) ,a  nil)
                (yesno   deleted   ,i!deleted               ,a ,a)
                (sexpr   keys      ,i!keys                  ,a ,a)
                (string  ip        ,i!ip                    ,e  nil))
    (if i!draft (+ fields `((yesno draft ,i!draft ,x ,x)))
        fields)))

; Should check valid-url etc here too.  In fact make a fn that
; does everything that has to happen after submitting a story,
; and call it both there and here.

(def edit-page (user i)
  (let here (edit-url i)
    (shortpage user nil nil "Edit" here
      (vars-form user
                 ((fieldfn* i!type) user i)
                 (fn (name val)
                     (unless (and (is name 'title) (len> val title-limit*))
                       (= (i name) val)))
                 (fn () (if (admin user) (pushnew 'locked i!keys))
                        (save-item i)
                        (astory&adjust-rank i)
                        (wipe (comment-cache* i!id))
                        (edit-page user i))
                 "update" nil t)
      (br2)
      (tab (tr (tag (td width '100% style 'padding-right:80px)
                 (tab (display-item nil i user here)))))
      (hook 'edit user i))))

 
; Comment Submission

(def comment-login-warning (parent whence (o text))
  (login-page 'login "You have to be logged in to comment."
              (fn (u ip)
                (ensure-news-user u)
                (newslog ip u 'comment-login)
                (addcomment-page parent u whence text))))

(def addcomment-page (parent user whence (o text) (o msg))
  (minipage "Add Comment"
    (pagemessage msg)
    (tab
      (let here (flink [addcomment-page parent (get-user _) whence text msg])
        (display-item nil parent user here))
      (spacerow 10)
      (row "" (comment-form parent user whence text)))))

; Comment forms last for 30 min (- cache time)

(def comment-form (parent user whence (o text))
  (tarform 1800
           (fn (req)
             (when-umatch/r user req
               (process-comment user parent (arg req "text") req!ip whence
                                (no (is (arg req "draft") nil)))))
    (textarea "text" 6 60  
      (aif text (prn it)))
    (pr " ")
    (tag (font size -2)
      (tag (a href formatdoc-url* target '_blank)
        (tag (font color (gray 175)) (pr "formatting help"))))
    (br2)
    (tag (button type 'submit
                 name "draft"
                 value "t"
                 onclick "needToConfirm = false;")
      (pr "save draft & preview"))
    (protected-submit (if (acomment parent) "reply" "add comment") t)))

(= comment-threshold* -20)

; Have to remove #\returns because a form gives you back "a\r\nb"
; instead of just "a\nb".   Maybe should just remove returns from
; the vals coming in from any form, e.g. in aform.

(def process-comment (user parent text ip whence draft)
  (if (no user)
       (flink [comment-login-warning parent whence text])
      (empty text)
       (flink [addcomment-page parent (get-user _) whence text retry*])
       (atlet c (create-comment parent text user ip draft)
         (submit-item user c)
         whence)))

(def create-comment (parent text user ip draft)
  (newslog ip user 'comment (parent 'id))
  (let c (inst 'item 'type 'comment 'id (new-item-id)
                     'text text 'parent parent!id 'by user 'ip ip 'draft draft)
    (save-item c)
    (= (items* c!id) c)
    (push c!id (itemkids* parent!id))
    (push c comments*)
    c))


; Comment Display

(def display-comment-tree (c user whence (o indent 0) (o initialpar))
  (when (cansee-descendant user c)
    (display-1comment c user whence indent initialpar)
    (display-subcomments c user whence (+ indent 1))))

(def display-1comment (c user whence indent showpar)
  (row (tab (display-comment nil c user whence t indent showpar showpar))))

(def display-subcomments (c user whence (o indent 0))
  (each k (sort (compare > frontpage-rank) (kids c))
    (display-comment-tree k user whence indent)))

(def display-comment (n c user whence (o astree) (o indent 0) 
                                      (o showpar) (o showon)
                                      (o show-immediate-parent))
  (let parent (item (c 'parent))
    (if (or (no show-immediate-parent)
            (and (cansee user parent) (cansee user (superparent c))))
      (tr (display-item-number n)
          (when astree (td (hspace (* indent 40))))
          (tag (td valign 'top) (votelinks-space))
            (if show-immediate-parent
              (tag (td width '100% style 'padding-right:80px)
                (tab
                  (if (is (parent 'type) 'comment)
                    (tr (display-comment-body parent user whence astree indent showpar showon))
                    (display-story nil parent user whence t t)))
                (tab
                  (spacerow 10)
                  (tr (tag (td width 40) "") (display-comment-body c user whence t indent showpar showon))
                  (spacerow 25)))
              (display-comment-body c user whence astree indent showpar showon))))))

; Comment caching doesn't make generation of comments significantly
; faster, but may speed up everything else by generating less garbage.

; It might solve the same problem more generally to make html code
; more efficient.

(= comment-cache* (table) comment-cache-timeout* (table) cc-window* 10000)

(= comments-printed* 0 cc-hits* 0)

(= comment-caching* t) 

; Cache comments generated for nil user that are over an hour old.
; Only try to cache most recent 10k items.  But this window moves,
; so if server is running a long time could have more than that in
; cache.  Probably should actively gc expired cache entries.

(def display-comment-body (c user whence astree indent showpar showon)
  (++ comments-printed*)
  (if (and comment-caching*
           astree (no showpar) (no showon)
           (live c)
           (nor (admin user) (editor user) (author user c))
           (< (- maxid* c!id) cc-window*)
           (> (- (seconds) c!time) 60)) ; was 3600
      (pr (cached-comment-body c user whence indent))
      (gen-comment-body c user whence astree indent showpar showon)))

(def cached-comment-body (c user whence indent)
  (or (and (> (or (comment-cache-timeout* c!id) 0) (seconds))
           (awhen (comment-cache* c!id)
             (++ cc-hits*)
             it))
      (= (comment-cache-timeout* c!id)
          (cc-timeout c!time)
         (comment-cache* c!id)
          (tostring (gen-comment-body c user whence t indent nil nil)))))

; Cache for the remainder of the current minute, hour, or day.

(def cc-timeout (t0)
  (let age (- (seconds) t0)
    (+ t0 (if (< age 3600)
               (* (+ (trunc (/ age    60)) 1)    60)
              (< age 86400)
               (* (+ (trunc (/ age  3600)) 1)  3600)
               (* (+ (trunc (/ age 86400)) 1) 86400)))))

(def gen-comment-body (c user whence astree indent showpar showon)
  (tag (td class 'default)
    (let parent (and (or (no astree) showpar) (c 'parent))
      (tag (div style "margin-top:2px; margin-bottom:-10px; ")
        (spanclass comhead
          (itemline c user whence)
          (permalink c user)
          (when parent
            (when (cansee user c) (pr bar*))
            (link "parent" (item-url ((item parent) 'id))))
          (editlink c user)
          (deletelink c user whence)
          (deadmark c user)
          (when showon
            (pr " | on: ")
            (let s (superparent c)
              (link (ellipsize s!title 50) (item-url s!id))))))
      (when (or parent (cansee user c))
        (br))
      (spanclass comment
        (if (~cansee user c)               (pr "[deleted]")
            (nor (live c) (author user c)) (spanclass dead (pr (item-text c)))
                                           (pr (item-text c))))
      (when (and astree (cansee user c) (live c))
        (para)
        (tag (font size 1)
          (if (and (~mem 'neutered c!keys)
                   (replyable c indent)
                   (comments-active c))
              (underline (replylink c whence))
              (fontcolor sand (pr "-----"))))))))

; For really deeply nested comments, caching could add another reply 
; delay, but that's ok.

; People could beat this by going to the link url or manually entering 
; the reply url, but deal with that if they do.

(= reply-decay* 1.8)   ; delays: (0 0 1 3 7 12 18 25 33 42 52 63)

(def replyable (c indent)
  (or (< indent 2)
      (> (item-age c) (expt (- indent 1) reply-decay*))))

(def replylink (i whence (o title 'reply))
  (link title (+ "reply?id=" i!id "&whence=" (urlencode whence))))

(newsop reply (id whence)
  (with (i      (safe-item id)
         whence (or (only.urldecode whence) "news"))
    (if (only.comments-active i)
        (if user
            (addcomment-page i user whence)
            (login-page 'login "You have to be logged in to comment."
                        (fn (u ip)
                          (ensure-news-user u)
                          (newslog ip u 'comment-login)
                          (addcomment-page i u whence))))
        (pr "No such item."))))


; Threads

(def threads-url (user) (+ "threads?id=" user))

(newsop threads (id) 
  (if id
      (threads-page user id)
      (pr "No user specified.")))

(def threads-page (user subject)
  (if (profile subject)
      (withs (title (+ subject "'s comments")
              label (if (is user subject) "my comments" title)
              here  (threads-url subject))
        (longpage-csb user (msec) nil label title here t
          (awhen (keep [and (cansee user _) (~subcomment _)]
                       (comments subject maxend*))
            (display-threads user it label title here))))
      (prn "No such user.")))

(def display-threads (user comments label title whence
                      (o start 0) (o end threads-perpage*))
  (tab 
    (each c (cut comments start end)
      (display-comment-tree c user whence 0 t))
    (when end
      (let newend (+ end threads-perpage*)
        (when (and (<= newend maxend*) (< end (len comments)))
          (spacerow 10)
          (row (tab (tr (td (hspace 0))
                        (td (hspace votewid*))
                        (td
                          (morelink display-threads
                                    comments label title end newend))))))))))

(def submissions (user (o limit)) 
  (map item (firstn limit (uvar user submitted))))

(def comments (user (o limit))
  (map item (retrieve limit acomment:item (uvar user submitted))))
  
(def subcomment (c)
  (some [and (acomment _) (is _!by c!by) (no _!deleted)]
        (ancestors c)))

(def ancestors (i)
  (accum a (trav i!parent a:item self:!parent:item)))


; Submitted

(def submitted-url (user) (+ "submitted?id=" user))
       
(newsop submitted (id) 
  (if id 
      (submitted-page user id)
      (pr "No user specified.")))

(def submitted-page (user subject)
  (if (profile subject)
      (withs (title (+ subject "'s posts")
              label (if (is user subject) "my posts" title)
              here  (submitted-url subject))
        (longpage-csb user (msec) nil label label here t
          (aif (keep [and (astory _) (cansee user _)]
                     (submissions subject))
               (display-items user it label label here 0 perpage* t t))))
      (pr "No such user.")))


; RSS

(newsop rss () (rsspage nil))

(newscache rsspage user 90 
  (rss-stories (retrieve perpage* live ranked-stories*)))

(def rss-stories (stories)
  (tag (rss version "2.0")
    (tag channel
      (tag title (pr this-site*))
      (tag link (pr site-url*))
      (tag description (pr site-desc*))
      (each s stories
        (tag item
          (let comurl (+ site-url* (item-url s!id))
            (tag title    (pr (eschtml s!title)))
            (tag link     (pr (if (blank s!url) comurl (eschtml s!url))))
            (tag comments (pr comurl))
            (tag description
              (cdata (link "Comments" comurl)))))))))


; User Stats

(newsop members () (memberspage user))

(newscache memberspage user 1000
  (longpage-csb user (msec) nil "members" "members" "members" t
    (sptab
      (let i 0
        (each u (sort (compare > [karma _])
                      (keep [pos [cansee nil _] (submissions _)] (users)))
          (tr (tdr:pr (++ i) ".")
              (td (userlink user u))
              (tdr:pr (* karma-multiplier* (karma u))))
          (if (is i 10) (spacerow 30)))))))

(adop editors ()
  (tab (each u (users [is (uvar _ auth) 1])
         (row (userlink user u)))))

; Ignore the most recent 5 comments since they may still be gaining votes.  
; Also ignore the highest-scoring comment, since possibly a fluff outlier.

(def comment-score (user)
  (aif (check (nthcdr 5 (comments user 50)) [len> _ 10])
       (avg (cdr (sort > (map realscore (rem !deleted it)))))
       nil))


; Comment Analysis

; Instead of a separate active op, should probably display this info 
; implicitly by e.g. changing color of commentlink or by showing the 
; no of comments since that user last looked.

(newsop active () (active-page user))

(newscache active-page user 600
  (listpage user (msec) (actives user) "active" "Active Threads"))

(def actives (user (o n maxend*) (o consider 2000))
  (visible user (rank-stories n consider (memo active-rank))))

(= active-threshold* 1500)

(def active-rank (s)
  (sum [max 0 (- active-threshold* (item-age _))]
       (cdr (family s))))

(def family (i) (cons i (mappend family (kids i))))


(newsop newcomments () (newcomments-page user))

(newscache newcomments-page user 60
  (listpage user (msec) (visible user (firstn maxend* comments*))
            "comments" "New Comments" "newcomments" nil nil t t))


; Doc

(defop formatdoc req
  (msgpage (get-user req) formatdoc* "Formatting Options"))

(= formatdoc-url* "formatdoc")

(= formatdoc* 
"Blank lines separate paragraphs.
<p> A paragraph beginning with a hash mark (#) is a subheading.
<p> A paragraph consisting of a single line with three or more
asterisks (***) will be rendered as a separator.
<p> The preview for a post consists of everything that appears
before the first subheading or separator.  If there are no
subheadings or separators, then the preview the first paragraph
(for long posts) or the entire post (for short posts).
<p> Text surrounded by dollar signs is rendered as LaTeX.
<p> Text after a blank line that is indented by two or more spaces is 
reproduced verbatim.  (This is intended for code.)
<p> Additional formatting options can be found at the
<a href=\"http://johnmacfarlane.net/pandoc/demo/example9/pandocs-markdown.html\">
Pandoc markdown documentation</a> page.<br><br>")


; Reset PW

(defopg resetpw req (resetpw-page (get-user req)))

(def resetpw-page (user (o msg))
  (minipage "Reset Password"
    (if msg (pr msg))
    (br2)
    (uform user req (try-resetpw user (arg req "p") (arg req "c"))
      (tab
        (tr
          (td (pr "new password: "))
          (td (gentag input type 'password name 'p value "" size 20)))
        (spacerow 5)
        (tr
          (td (pr "confirmation: "))
          (td (gentag input type 'password name 'c value "" size 20)))
        (spacerow 15)
        (tr
          (tag (td colspan 2) (submit "reset")))))))

(def try-resetpw (user newpw confirm)
  (if (no (is newpw confirm))
      (resetpw-page user "Passwords do not match.
                          Please try again.")
      (len< newpw 4)
      (resetpw-page user "Passwords should be a least 4 characters long.  
                          Please choose another.")
      (do (set-pw user newpw)
          (newspage user))))



; Stats

(adop optimes ()
  (sptab
    (tr (td "op") (tdr "avg") (tdr "med") (tdr "req") (tdr "total"))
    (spacerow 10)
    (each name (sort < newsop-names*)
      (tr (td name)
          (let ms (only.avg (qlist (optimes* name)))
            (tdr:prt (only.round ms))
            (tdr:prt (only.med (qlist (optimes* name))))
            (let n (opcounts* name)
              (tdr:prt n)
              (tdr:prt (and n (round (/ (* n ms) 1000))))))))))

