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
  avg        nil
  weight     .5
  ignore     nil
  email      nil
  about      nil
  showdead   nil
  noprocrast nil
  firstview  nil
  lastview   nil
  maxvisit   20 
  minaway    180
  topcolor   nil
  keys       nil
  delay      0)

(deftem item
  id         nil
  type       nil
  by         nil
  ip         nil
  time       (seconds)
  title      nil
  text       nil
  likes      nil   ; list of users, not including item!by
  score      0
  sockvotes  0
  flags      nil
  dead       nil
  deleted    nil
  parts      nil
  parent     nil
  kids       nil
  keys       nil)


; Load and Save

(= newsdir*  "arc/news/"
   storydir* "arc/news/story/"
   profdir*  "arc/news/profile/"
   votedir*  "arc/news/vote/")

(= votes* (table) profs* (table))

(def nsv ((o port 8080))
  (map ensure-dir (list arcdir* newsdir* storydir* votedir* profdir*))
  (unless stories* (load-items))
  (if (empty profs*) (load-users))
  (asv port))

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
(mac ignored (u) `(uvar ,u ignore))

; Note that users will now only consider currently loaded users.

(def users ((o f idfn)) 
  (keep f (keys profs*)))

(def check-key (u k)
  (and u (mem k (uvar u keys))))

(def author (u i) (is u i!by))


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
         ids   (sort > (map int (dir storydir*))))
    (if ids (= maxid* (car ids)))
    (noisy-each 100 id (firstn initload* ids)
      (let i (load-item id)
        (push i (items i!type))))
    (= stories*  (rev (merge (compare < !id) items!story items!poll))
       comments* (rev items!comment))
    (hook 'initload items))
  (ensure-topstories))

(def ensure-topstories ()
  (aif (errsafe (readfile1 (+ newsdir* "topstories")))
       (= ranked-stories* (map item it))
       (do (prn "ranking stories.") 
           (flushout)
           (gen-topstories))))

(def astory   (i) (is i!type 'story))
(def acomment (i) (is i!type 'comment))
(def apoll    (i) (is i!type 'poll))

(def load-item (id)
  (= (items* id) (temload 'item (+ storydir* id))))

(def new-item-id ()
  (evtil (++ maxid*) [~file-exists (+ storydir* _)]))

(def item (id)
  (or (items* id) (errsafe:load-item id)))

(def kids (i) (map item i!kids))

; For use on external item references (from urls).  Checks id is int 
; because people try e.g. item?id=363/blank.php

(def safe-item (id)
  (ok-id&item (if (isa id 'string) (saferead id) id)))

(def ok-id (id) 
  (and (exact id) (<= 1 id maxid*)))

(def arg->item (req key)
  (safe-item:saferead (arg req key)))

(def live (i) (nor i!dead i!deleted))

(def save-item (i) (save-table i (+ storydir* i!id)))

(def kill (i how)
  (unless i!dead
    (log-kill i how)
    (wipe (comment-cache* i!id))
    (set i!dead)
    (save-item i)))

(= kill-log* nil)

(def log-kill (i how)
  (push (list i!id how) kill-log*))

(mac each-loaded-item (var . body)
  (w/uniq g
    `(let ,g nil
       (loop (= ,g maxid*) (> ,g 0) (-- ,g)
         (whenlet ,var (items* ,g)
           ,@body)))))

(def loaded-items (test)
  (accum a (each-loaded-item i (test&a i))))

(def newslog args (apply srvlog 'news args))

(def votelog args (apply srvlog 'votes args))


; Ranking

; Votes divided by the age in hours to the gravityth power.
; Would be interesting to scale gravity in a slider.

(= gravity* 1.8 timebase* 120 front-threshold* 1)

(def frontpage-rank (s (o scorefn realscore) (o gravity gravity*))
  (* (/ (let base (- (scorefn s) 1)
          (if (> base 0) (expt base .8) base))
        (expt (/ (+ (item-age s) timebase*) 60) gravity))
     (if (no (in s!type 'story 'poll))  .5
                                        (contro-factor s))))

(def contro-factor (s)
  (aif (check (visible-family nil s) [> _ 20])
       (min 1 (expt (/ (realscore s) it) 2))
       1))

(def realscore (i) (+ 1 (- i!score i!sockvotes)))

(def item-age (i) (minutes-since i!time))

(def user-age (u) (minutes-since (uvar u created)))

; Only looks at the 1000 most recent stories, which might one day be a 
; problem if there is massive spam. 

(def gen-topstories ()
  (= ranked-stories* (rank-stories 180 1000 (memo frontpage-rank))))

(def save-topstories ()
  (writefile (map !id (firstn 180 ranked-stories*))
             (+ newsdir* "topstories")))
 
(def rank-stories (n consider scorefn)
  (bestn n (compare > scorefn) (latest-items metastory nil consider)))

; With virtual lists the above call to latest-items could be simply:
; (map item (retrieve consider metastory:item (gen maxid* [- _ 1])))

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
             
; redefined later

(def metastory (i) (and i (in i!type 'story 'poll)))

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
      i!dead      (or (author user i) (seesdead user))
      (delayed i) (author user i)
      t))

(let mature (table)
  (def delayed (i)
    (and (no (mature i!id))
         (acomment i)
         (or (< (item-age i) (min max-delay* (uvar i!by delay)))
             (do (set (mature i!id))
                 nil)))))

(def seesdead (user)
  (or (and user (uvar user showdead) (no (ignored user)))
      (editor user)))

(def visible (user is)
  (keep [cansee user _] is))

(def cansee-descendant (user c)
  (or (cansee user c)
      (some [cansee-descendant user (item _)] 
            c!kids)))
  
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
         (if (check-procrast ,gu)
             (do (pagetop 'full ,gi ,gl ,gt ,gu ,gw)
                 (hook 'page ,gu ,gl)
                 ,@body)
             (row (procrast-msg ,gu ,gw)))))))

(mac longpage (user t1 lid label title whence . body)
  (w/uniq (gu gt gi)
    `(with (,gu ,user ,gt ,t1 ,gi ,lid)
       (fulltop ,gu ,gi ,label ,title ,whence
         (trtd ,@body)
         (trtd (vspace 10)
               (color-stripe (main-color ,gu))
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
  (let utext (unmarkdown text)
    (if (<= (len utext) maxlen) utext
      (word-boundary (cut utext 0 maxlen)))))
  
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

td > h1 { font-family:Verdana; font-size:14pt; color:#000000; font-weight:bold; }

table td.csb      { background-color:#e6e6e6; width:300px; padding:8px; font-size:10pt; }
table td.csb > h3 { font-family:Verdana; font-size:12pt; font-weight:bold; }
table td.contents { margin:0; padding-right:80; }
table td.story    { line-height:135%; }

.admin td   { font-family:Verdana; font-size:10.5pt; color:#000000; }
.subtext td { font-family:Verdana; font-size:  10pt; color:#828282; }

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

.comment a:link, .comment a:visited { text-decoration:underline; }
.dead a:link, .dead a:visited { color:#dddddd; }
.pagetop a:visited { color:#000000;}
.topsel a:link, .topsel a:visited { color:#ffffff; }

.subtext a:link, .subtext a:visited { color:#828282; }
.subtext a:hover { text-decoration:underline; }

.csb a:link, .csb a:visited { color:#828282; }
.csb a:hover { text-decoration:underline; }

.comhead a:link, .subtext a:visited { color:#828282; }
.comhead a:hover { text-decoration:underline; }

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

(def main-color (user) 
  (aif (and user (uvar user topcolor))
       (hex>color it)
       site-color*))

(def pagetop (switch lid label (o title) (o user) (o whence))
; (tr (tdcolor black (vspace 5)))
  (tr (tdcolor (main-color user)
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
    (userlink user user nil)
    (when showkarma (pr  "&nbsp;(@(karma user))"))
    (pr "&nbsp;|&nbsp;"))
  (if user
      (rlinkf 'logout (req)
        (when-umatch/r user req
          (logout-user user)
          whence))
      (onlink "login"
        (login-page 'both nil 
                    (list (fn (u ip) 
                            (ensure-news-user u)
                            (newslog ip u 'top-login))
                          whence)))))


; News-Specific Defop Variants

(mac defopt (name parm test msg . body)
  `(defop ,name ,parm
     (if (,test (get-user ,parm))
         (do ,@body)
         (login-page 'both (+ "Please log in" ,msg ".")
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
  `((num      caching         ,caching*                       t t)
    (bigtoks  comment-kill    ,comment-kill*                  t t)
    (bigtoks  comment-ignore  ,comment-ignore*                t t)))

; Need a util like vars-form for a collection of variables.
; Or could generalize vars-form to think of places (in the setf sense).

(def newsadmin-page (user)
  (shortpage user nil nil "newsadmin" "newsadmin"
    (vars-form user 
               (nad-fields)
               (fn (name val)
                 (case name
                   caching            (= caching* val)
                   comment-kill       (todisk comment-kill* val)
                   comment-ignore     (todisk comment-ignore* val)
                   ))
               (fn () (newsadmin-page user))) 
    (br2)
    (aform (fn (req)
             (with (user (get-user req) subject (arg req "id"))
               (if (profile subject)
                   (do (killallby subject)
                       (submitted-page user subject))
                   (admin&newsadmin-page user))))
      (single-input "" 'id 20 "kill all by"))
    (br2)
    (aform (fn (req)
             (let user (get-user req)
               (set-ip-ban user (arg req "ip") t)
               (admin&newsadmin-page user)))
      (single-input "" 'ip 20 "ban ip"))))


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
                 (when (and (is name 'ignore) val (no prof!ignore))
                   (log-ignore user subject 'profile))
                 (= (prof name) val))
               (fn () (save-prof subject)
                      (user-page user subject)))))

(= topcolor-threshold* 250)

(def user-fields (user subject)
  (withs (e (editor user) 
          a (admin user) 
          w (is user subject)
          k (and w (> (karma user) topcolor-threshold*))
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
      (num     avg        ,(p 'avg)                                ,a  nil)
      (yesno   ignore     ,(p 'ignore)                             ,e  ,e)
      (num     weight     ,(p 'weight)                             ,a  ,a)
      (mdtext2 about      ,(p 'about)                               t  ,u)
      (string  email      ,(p 'email)                              ,u  ,u)
      (yesno   showdead   ,(p 'showdead)                           ,u  ,u)
      (yesno   noprocrast ,(p 'noprocrast)                         ,u  ,u)
      (string  firstview  ,(p 'firstview)                          ,a   nil)
      (string  lastview   ,(p 'lastview)                           ,a   nil)
      (posint  maxvisit   ,(p 'maxvisit)                           ,u  ,u)
      (posint  minaway    ,(p 'minaway)                            ,u  ,u)
      (sexpr   keys       ,(p 'keys)                               ,a  ,a)
      (hexcol  topcolor   ,(or (p 'topcolor) (hexrep site-color*)) ,k  ,k)
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

(= caching* 1 perpage* 30 threads-perpage* 10 maxend* 210 
   csb-count* 5 csb-maxlen* 30 preview-maxlen* 1000)

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

(newscache newspage user 90
  (listpage user (msec) (topstories user maxend*) nil nil "news" nil t))

(def listpage (user t1 items label title 
               (o url label) (o number t) (o show-comments t) (o preview-only t))
  (hook 'listpage user)
  (longpage-csb user t1 nil label title url show-comments
    (display-items user items label title url 0 perpage* number preview-only)))


(newsop newest () (newestpage user))

; Note: dead/deleted items will persist for the remaining life of the 
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
        (map row:link
             '(optimes topips flagged killed badguys badlogins goodlogins)))
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
                    (o start 0) (o end perpage*) (o number) (o preview-only))
  (zerotable
    (let n start
      (each i (cut items start end)
        (trtd (tab (display-item (and number (++ n)) i user whence t preview-only)
             (spacerow (if (acomment i) 15 30))))))
    (when end
      (let newend (+ end perpage*)
        (when (and (<= newend maxend*) (< end (len items)))
          (spacerow 10)
          (tr (tag (td colspan (if number 2 1)))
              (tag (td class 'title)
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

(def display-story (i s user whence preview-only)
  (when (or (cansee user s) (s 'kids))
    (tr (td (votelinks-space))
        (display-item-number i)
        (titleline s user whence))
    (tr (tag (td colspan (if i 2 1)))    
        (tag (td class 'subtext)
          (hook 'itemline s user)
          (itemline s user whence)
          (when (in s!type 'story 'poll) (commentlink s user))
          (editlink s user)
          (when (apoll s) (addoptlink s user))
          (unless i (flaglink s user whence))
          (killlink s user whence)
          (blastlink s user whence)
          (blastlink s user whence t)
          (deletelink s user whence)))
    (spacerow 10)
    (tr (tag (td colspan (if i 2 1)))
        (tag (td class 'story) (display-item-text s user preview-only)))))

(def display-item-number (i)
  (when i (tag (td align 'right valign 'top class 'title)
            (pr i "."))))

(def titleline (s user whence)
  (tag (td class 'title)
    (if (cansee user s)
        (do (deadmark s user)
            (link s!title (item-url s!id)))
        (pr (pseudo-text s)))))
      
(def pseudo-text (i)
  (if i!deleted "[deleted]" "[dead]"))

(def deadmark (i user)
  (when (and i!dead (seesdead user))
    (pr " [dead] "))
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
         (login-page 'both "You have to be logged in to vote."
                     (list (fn (u ip)
                             (ensure-news-user u)
                             (newslog ip u 'vote-login)
                             (when (canvote u i dir)
                               (vote-for u i dir)
                               (logvote ip u i)))
                           whence))
        (canvote user i dir)
         (do (vote-for by i dir)
             (logvote ip by i)
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
  (+ (if (mem user i!likes) (list user) '())
     (sort < (rem user i!likes))))

(def itemscore (i (o user))
  (tag (span id (+ "score_" i!id))
    (pr (plural (len (likes i user)) "like")))
  (hook 'itemscore i user))

(def byline (i user)
  (pr " by @(tostring (userlink user i!by)) @(text-age:item-age i) "))

(def user-url (user) (+ "user?id=" user))

(= show-avg* nil)

(def userlink (user subject (o show-avg t))
  (clink userlink (user-name user subject) (user-url subject))
  (awhen (and show-avg* (admin user) show-avg (uvar subject avg))
    (pr " (@(num it 1 t t))")))

(def userlink-or-you (user subject)
  (if (is user subject) (spanclass you (pr "You")) (userlink user subject)))

(def user-name (user subject)
  (if (and (editor user) (ignored subject))
       (tostring (fontcolor darkred (pr subject)))
      subject))

(= show-threadavg* nil)

(def commentlink (i user)
  (when (cansee user i) 
    (pr bar*)
    (tag (a href (item-url i!id))
      (let n (- (visible-family user i) 1)
        (if (> n 0)
            (do (pr (plural n "comment"))
                (awhen (and show-threadavg* (admin user) (threadavg i))
                  (pr " (@(num it 1 t t))")))
            (pr "discuss"))))))

(def visible-family (user i)
  (+ (if (cansee user i) 1 0)
     (sum [visible-family user (item _)] i!kids)))

(def threadavg (i)
  (only.avg (map [or (uvar _ avg) 1] 
                 (rem admin (dedup (map !by (keep live (family i))))))))

(= user-changetime* 120 editor-changetime* 1440)

(= everchange* (table) noedit* (table))

(def canedit (user i)
  (or (admin user)
      (and (~noedit* i!type)
           (editor user) 
           (< (item-age i) editor-changetime*))
      (own-changeable-item user i)))

(def own-changeable-item (user i)
  (and (author user i)
       (~mem 'locked i!keys)
       (no i!deleted)
       (or (everchange* i!type)
           (< (item-age i) user-changetime*))))

(def editlink (i user)
  (when (canedit user i)
    (pr bar*)
    (link "edit" (edit-url i))))

(def addoptlink (p user)
  (when (or (admin user) (author user p))
    (pr bar*)
    (onlink "add choice" (add-pollopt-page p user))))

; reset later

(= flag-threshold* 30 flag-kill-threshold* 7 many-flags* 1)

; Un-flagging something doesn't unkill it, if it's now no longer
; over flag-kill-threshold.  Ok, since arbitrary threshold anyway.

(def flaglink (i user whence)
  (when (and user
             (isnt user i!by)
             (or (admin user) (> (karma user) flag-threshold*)))
    (pr bar*)
    (w/rlink (do (togglemem user i!flags)
                 (when (and (~mem 'nokill i!keys)
                            (len> i!flags flag-kill-threshold*)
                            (< (realscore i) 10)
                            (~admin i!by)
                            (~find admin i!likes))
                   (kill i 'flags))
                 whence)
      (pr "@(if (mem user i!flags) 'un)flag"))
    (when (and (admin user) (len> i!flags many-flags*))
      (pr bar* (plural (len i!flags) "flag") " ")
      (w/rlink (do (togglemem 'nokill i!keys)
                   (save-item i)
                   whence)
        (pr (if (mem 'nokill i!keys) "un-notice" "noted"))))))

(def killlink (i user whence)
  (when (admin user)
    (pr bar*)
    (w/rlink (do (zap no i!dead)
                 (if i!dead 
                     (do (pull 'nokill i!keys)
                         (log-kill i user))
                     (pushnew 'nokill i!keys))
                 (save-item i)
                 whence)
      (pr "@(if i!dead 'un)kill"))))

; Blast kills the submission and bans the user.  Nuke also bans the 
; site, so that all future submitters will be ignored.  Does not ban 
; the ip address, but that will eventually get banned by maybe-ban-ip.

(def blastlink (i user whence (o nuke))
  (when (and (admin user) 
             (or (no nuke) (~empty i!url)))
    (pr bar*)
    (w/rlink (do (toggle-blast i user nuke)
                 whence)
      (prt (if (ignored i!by) "un-") (if nuke "nuke" "blast")))))

(def toggle-blast (i user (o nuke))
  (atomic
    (if (ignored i!by)
        (do (wipe i!dead (ignored i!by))
            (awhen (and nuke (sitename i!url))
              (set-site-ban user it nil)))
        (do (set i!dead)
            (ignore user i!by (if nuke 'nuke 'blast))
            (awhen (and nuke (sitename i!url))
              (set-site-ban user it 'ignore))))
    (if i!dead (log-kill i user))
    (save-item i)
    (save-prof i!by)))

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

(def logvote (ip user story)
  (newslog ip user 'vote (story 'id) (list (story 'title))))

(def text-age (a)
  (tostring
    (if (>= a 1440) (pr (plural (trunc (/ a 1440)) "day")    " ago")
        (>= a   60) (pr (plural (trunc (/ a 60))   "hour")   " ago")
                    (pr (plural (trunc a)          "minute") " ago"))))


; Voting

; A user needs legit-threshold karma for a vote to count if there has 
; already been a vote from the same IP address.  A new account below both
; new- thresholds won't affect rankings, though such votes still affect 
; scores unless not a legit-user.

(= legit-threshold* 0 new-age-threshold* 0 new-karma-threshold* 2)

(def legit-user (user) 
  (or (editor user)
      (> (karma user) legit-threshold*)))

(def possible-sockpuppet (user)
  (or (ignored user)
      (< (uvar user weight) .5)
      (and (< (user-age user) new-age-threshold*)
           (< (karma user) new-karma-threshold*))))

(= downvote-ratio-limit* .65 recent-votes* nil votewindow* 100)

; Note: if vote-for by one user changes (s 'score) while s is being
; edited by another, the save after the edit will overwrite the change.
; Actual votes can't be lost because that field is not editable.  Not a
; big enough problem to drag in locking.

(def vote-for (user i (o dir 'like))
  (unless (or (is (vote user i) dir)
              (is user i!by)
              (and (~live i) (isnt user i!by)))
    (withs (ip   (logins* user)
            vote (list (seconds) ip user dir i!score))
      (unless (or (ignored user) (check-key user 'novote))
        (++ i!score (case dir like 1 nil -1))
        ; canvote protects against sockpuppet downvote of comments 
        (when (and (is dir 'like) (possible-sockpuppet user))
          (++ i!sockvotes))
        (metastory&adjust-rank i)
        (unless (is i!type 'pollopt)
          (++ (karma i!by) (case dir like 1 nil -1))
          (save-prof i!by))
        (wipe (comment-cache* i!id)))
      (if (admin user) (pushnew 'nokill i!keys))
      (if (is dir 'like) (pushnew user i!likes)
                         (zap [rem user _] i!likes))
      (save-item i)
      (= ((votes* user) i!id) dir)
      (save-votes user)
      (push (cons i!id vote) recent-votes*))))

; redefined later

(def biased-voter (i vote) nil)

; ugly to access vote fields by position number

; TODO: remove this rather than just setting to 0
(def downvote-ratio (user (o sample 20))
  0)

(def just-downvoted (user victim (o n 3))
  (let prev (firstn n (recent-votes-by user))
    (and (is (len prev) n)
         (all (fn ((id sec ip voter dir score))
                (and (author victim (item id)) (is dir 'down)))
              prev))))

; Ugly to pluck out fourth element.  Should read votes into a vote
; template.  They're stored slightly differently in two diff places: 
; in one with the voter in the car and the other without.

(def recent-votes-by (user)
  (keep [is _.3 user] recent-votes*))


; Story Submission

(newsop submit ()
  (if user 
      (submit-page user "" t) 
      (submit-login-warning "" t)))

(def submit-login-warning ((o title) (o showtext) (o text))
  (login-page 'both "You have to be logged in to submit."
              (fn (user ip) 
                (ensure-news-user user)
                (newslog ip user 'submit-login)
                (submit-page user title showtext text))))

(def submit-page (user (o title) (o showtext) (o text "") (o msg))
  (minipage "Submit"
    (pagemessage msg)
    (urform user req
            (process-story (get-user req)
                           (striptags (arg req "t"))
                           showtext
                           (and showtext (md-from-form (arg req "x") t))
                           req!ip)
      (tab
        (row "title"  (input "t" title 50))
        (row "text" (textarea "x" 4 50 (only.pr text)))
        (row "" (submit))
        (spacerow 20)
        (row "" submit-instructions*)))))

(= submit-instructions*
   "Leave url blank to submit a question for discussion. If there is 
    no url, the text (if any) will appear at the top of the comments 
    page. If there is a url, the text will be ignored.")

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

; Only for annoyingly high-volume spammers. For ordinary spammers it's
; enough to ban their sites and ip addresses.

(disktable big-spamsites* (+ newsdir* "big-spamsites"))

(def process-story (user title showtext text ip)
  (if (no user)
       (flink [submit-login-warning title showtext text])
      (or (blank title) (blank text))
       (flink [submit-page user title showtext text blanktext*])
      (len> title title-limit*)
       (flink [submit-page user title showtext text toolong*])
      (let s (create-story title text user ip)
        (submit-item user s)
        "newest")))

(def submit-item (user i)
  (push i!id (uvar user submitted))
  (save-prof user)
  (metastory&adjust-rank i))

(def create-story (title text user ip)
  (newslog ip user 'create (list title))
  (let s (inst 'item 'type 'story 'id (new-item-id) 
                     'title title 'text text 'by user 'ip ip)
    (save-item s)
    (= (items* s!id) s)
    (push s stories*)
    s))


; Polls

; a way to add a karma threshold for voting in a poll
;  or better still an arbitrary test fn, or at least pair of name/threshold.
; option to sort the elements of a poll when displaying
; exclusive field? (means only allow one vote per poll)

(= poll-threshold* 20)

(newsop newpoll ()
  (if (and user (> (karma user) poll-threshold*))
      (newpoll-page user)
      (pr "Sorry, you need @poll-threshold* karma to create a poll.")))
  
(def newpoll-page (user (o title "Poll: ") (o text "") (o opts "") (o msg))
  (minipage "New Poll"
    (pagemessage msg)
    (urform user req
            (process-poll (get-user req)
                          (striptags (arg req "t"))
                          (md-from-form (arg req "x") t)
                          (striptags (arg req "o"))
                          req!ip)
      (tab   
        (row "title"   (input "t" title 50))
        (row "text"    (textarea "x" 4 50 (only.pr text)))
        (row ""        "Use blank lines to separate choices:")
        (row "choices" (textarea "o" 7 50 (only.pr opts)))
        (row ""        (submit))))))

(= fewopts* "A poll must have at least two options.")

(def process-poll (user title text opts ip)
  (if (or (blank title) (blank opts))
       (flink [newpoll-page user title text opts retry*])
      (len> title title-limit*)
       (flink [newpoll-page user title text opts toolong*])
      (len< (paras opts) 2)
       (flink [newpoll-page user title text opts fewopts*])
      (atlet p (create-poll title text opts user ip)
        (submit-item user p)
        "newest")))

(def create-poll (title text opts user ip)
  (newslog ip user 'create-poll title)
  (let p (inst 'item 'type 'poll 'id (new-item-id)
                     'title title 'text text 'by user 'ip ip)
    (= p!parts (map get!id (map [create-pollopt p nil nil _ user ip]
                                (paras opts))))
    (save-item p)
    (= (items* p!id) p)
    (push p stories*)
    p))

(def create-pollopt (p title text user ip)
  (let o (inst 'item 'type 'pollopt 'id (new-item-id)
                     'title title 'text text 'parent p!id
                     'by user 'ip ip)
    (save-item o)
    (= (items* o!id) o) 
    o))

(def add-pollopt-page (p user)
  (minipage "Add Poll Choice"
    (urform user req
            (do (add-pollopt user p (striptags (arg req "x")) req!ip)
                (item-url p!id))
      (tab
        (row "text" (textarea "x" 4 50))
        (row ""     (submit))))))

(def add-pollopt (user p text ip)
  (unless (blank text)
    (atlet o (create-pollopt p nil nil text user ip)
      (++ p!parts (list o!id))
      (save-item p))))

(def display-pollopts (p user whence)
  (each o (visible user (map item p!parts))
    (display-pollopt nil o user whence)
    (spacerow 7)))

(def display-pollopt (n o user whence)
  (tr (display-item-number n)
      (tag (td valign 'top)
        (votelinks-space))
      (tag (td class 'comment)
        (tag (div style "margin-top:1px;margin-bottom:0px")
          (if (~cansee user o) (pr (pseudo-text o))
              (~live o)        (spanclass dead 
                                 (pr (if (~blank o!title) o!title o!text)))
                               (fontcolor black (pr o!text))))))
  (tr (if n (td))
      (td)
      (tag (td class 'default)
        (spanclass comhead
          (itemscore o)
          (editlink o user)
          (killlink o user whence)
          (deletelink o user whence)
          (deadmark o user)))))


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

(def news-type (i) (and i (in i!type 'story 'comment 'poll 'pollopt)))

(def item-page (user i)
  (with (title (and (cansee user i)
                    (or i!title (aand i!text (ellipsize (striptags it)))))
         here (item-url i!id))
    (longpage-csb user (msec) nil nil title here t
      (tab (display-item nil i user here)
           (when (apoll i)
             (spacerow 10)
             (tr (td)
                 (td (tab (display-pollopts i user here)))))
           (when (and (cansee user i) (comments-active i))
             (spacerow 10)
             (row "" (comment-form i user here))))
      (br2) 
      (when (and i!kids (commentable i))
        (tab (display-subcomments i user here))
        (br2)))))

(def commentable (i) (in i!type 'story 'comment 'poll))

; By default the ability to comment on an item is turned off after 
; 45 days, but this can be overriden with commentable key.

(= commentable-threshold* (* 60 24 45))

(def comments-active (i)
  (and (live&commentable i)
       (live (superparent i))
       (or (< (item-age i) commentable-threshold*)
           (mem 'commentable i!keys))))


(= displayfn* (table))

(= (displayfn* 'story)   (fn (n i user here inlist preview-only)
                           (display-story n i user here preview-only)))

(= (displayfn* 'comment) (fn (n i user here inlist preview-only)
                           (display-comment n i user here nil 0 nil inlist)))

(= (displayfn* 'poll)    (displayfn* 'story))

(= (displayfn* 'pollopt) (fn (n i user here inlist preview-only)
                           (display-pollopt n i user here)))

(def display-item (n i user here (o inlist) (o preview-only))
  ((displayfn* (i 'type)) n i user here inlist preview-only))

(def superparent (i)
  (aif i!parent (superparent:item it) i))

(def first-para (text)
  (let index (posmatch "<p>" text)
    (if (no index) text
      (cut text 0 index))))

(def preview (text)
  (if (<= (len text) preview-maxlen*) text
    (first-para text)))

(def display-item-text (s user preview-only)
  (when (and (cansee user s) 
             (in s!type 'story 'poll))
    (if preview-only (pr (preview s!text))
      (pr s!text))))


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
       `((string1 title     ,s!title        t ,x)
         (mdtext2 text      ,s!text         t ,x)
         ,@(standard-item-fields s a e x)))))

(= (fieldfn* 'comment)
   (fn (user c)
     (with (a (admin user)  e (editor user)  x (canedit user c))
       `((mdtext  text      ,c!text         t ,x)
         ,@(standard-item-fields c a e x)))))

(= (fieldfn* 'poll)
   (fn (user p)
     (with (a (admin user)  e (editor user)  x (canedit user p))
       `((string1 title     ,p!title        t ,x)
         (mdtext2 text      ,p!text         t ,x)
         ,@(standard-item-fields p a e x)))))

(= (fieldfn* 'pollopt)
   (fn (user p)
     (with (a (admin user)  e (editor user)  x (canedit user p))
       `((string  title     ,p!title        t ,x)
         (mdtext2 text      ,p!text         t ,x)
         ,@(standard-item-fields p a e x)))))

(def standard-item-fields (i a e x)
       `((int     likes     ,(len i!likes) ,a  nil)
         (int     score     ,i!score        t ,a)
         (int     sockvotes ,i!sockvotes   ,a ,a)
         (yesno   dead      ,i!dead        ,e ,e)
         (yesno   deleted   ,i!deleted     ,a ,a)
         (sexpr   flags     ,i!flags       ,a nil)
         (sexpr   keys      ,i!keys        ,a ,a)
         (string  ip        ,i!ip          ,e  nil)))

; Should check valid-url etc here too.  In fact make a fn that
; does everything that has to happen after submitting a story,
; and call it both there and here.

(def edit-page (user i)
  (let here (edit-url i)
    (shortpage user nil nil "Edit" here
      (tab (display-item nil i user here))
      (br2)
      (vars-form user
                 ((fieldfn* i!type) user i)
                 (fn (name val) 
                   (unless (ignore-edit user i name val)
                     (when (and (is name 'dead) val (no i!dead))
                       (log-kill i user))
                     (= (i name) val)))
                 (fn () (if (admin user) (pushnew 'locked i!keys))
                        (save-item i)
                        (metastory&adjust-rank i)
                        (wipe (comment-cache* i!id))
                        (edit-page user i)))
      (hook 'edit user i))))

(def ignore-edit (user i name val)
  (case name title (len> val title-limit*)
             dead  (and (mem 'nokill i!keys) (~admin user))))

 
; Comment Submission

(def comment-login-warning (parent whence (o text))
  (login-page 'both "You have to be logged in to comment."
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
               (process-comment user parent (arg req "text") req!ip whence)))
    (textarea "text" 6 60  
      (aif text (prn (unmarkdown it))))
    (br2)
    (submit (if (acomment parent) "reply" "add comment"))))

(= comment-threshold* -20)

; Have to remove #\returns because a form gives you back "a\r\nb"
; instead of just "a\nb".   Maybe should just remove returns from
; the vals coming in from any form, e.g. in aform.

(def process-comment (user parent text ip whence)
  (if (no user)
       (flink [comment-login-warning parent whence text])
      (empty text)
       (flink [addcomment-page parent (get-user _) whence text retry*])
       (atlet c (create-comment parent (md-from-form text) user ip)
         (submit-item user c)
         whence)))

(def bad-user (u)
  (or (ignored u) (< (karma u) comment-threshold*)))

(def create-comment (parent text user ip)
  (newslog ip user 'comment (parent 'id))
  (let c (inst 'item 'type 'comment 'id (new-item-id)
                     'text text 'parent parent!id 'by user 'ip ip)
    (save-item c)
    (= (items* c!id) c)
    (push c!id parent!kids)
    (save-item parent)
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
  (each k (sort (compare > frontpage-rank:item) c!kids)
    (display-comment-tree (item k) user whence indent)))

(def display-comment (n c user whence (o astree) (o indent 0) 
                                      (o showpar) (o showon))
  (tr (display-item-number n)
      (when astree (td (hspace (* indent 40))))
      (tag (td valign 'top) (votelinks-space))
      (display-comment-body c user whence astree indent showpar showon)))

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
          ; a hack to check whence but otherwise need an arg just for this
          (unless (or astree (is whence "newcomments"))
            (flaglink c user whence))
          (deadmark c user)
          (when showon
            (pr " | on: ")
            (let s (superparent c)
              (link (ellipsize s!title 50) (item-url s!id))))))
      (when (or parent (cansee user c))
        (br))
      (spanclass comment
        (if (~cansee user c)               (pr (pseudo-text c))
            (nor (live c) (author user c)) (spanclass dead (pr c!text))
                                           (fontcolor (comment-color c)
                                             (pr c!text))))
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
            (login-page 'both "You have to be logged in to comment."
                        (fn (u ip)
                          (ensure-news-user u)
                          (newslog ip u 'comment-login)
                          (addcomment-page i u whence))))
        (pr "No such item."))))

(def comment-color (c)
  (if (>= c!score 0) black (grayrange c!score)))

(defmemo grayrange (s)
  (gray (min 230 (round (expt (* (+ (abs s) 1) 900) .6)))))


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
                        (tag (td class 'title)
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
          (if (or (no (ignored subject))
                  (is user subject)
                  (seesdead user))
              (aif (keep [and (metastory _) (cansee user _)]
                         (submissions subject))
                   (display-items user it label label here 0 perpage* t t)))))
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
              (td (userlink user u nil))
              (tdr:pr (karma u))
              (when (admin user)
                (tdr:prt (only.num (uvar u avg) 2 t t))))
          (if (is i 10) (spacerow 30)))))))

(adop editors ()
  (tab (each u (users [is (uvar _ auth) 1])
         (row (userlink user u)))))


(= update-avg-threshold* 0)  ; redefined later

(defbg update-avg 45
  (unless (or (empty profs*) (no stories*))
    (update-avg (rand-user [and (only.> (car (uvar _ submitted)) 
                                        (- maxid* initload*))
                                (len> (uvar _ submitted) 
                                      update-avg-threshold*)]))))

(def update-avg (user)
  (= (uvar user avg) (comment-score user))
  (save-prof user))

(def rand-user ((o test idfn))
  (evtil (rand-key profs*) test))

; Ignore the most recent 5 comments since they may still be gaining votes.  
; Also ignore the highest-scoring comment, since possibly a fluff outlier.

(def comment-score (user)
  (aif (check (nthcdr 5 (comments user 50)) [len> _ 10])
       (avg (cdr (sort > (map !score (rem !deleted it)))))
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

(def family (i) (cons i (mappend family:item i!kids)))


(newsop newcomments () (newcomments-page user))

(newscache newcomments-page user 60
  (listpage user (msec) (visible user (firstn maxend* comments*))
            "comments" "New Comments" "newcomments" nil nil))


; Doc

(defop formatdoc req
  (msgpage (get-user req) formatdoc* "Formatting Options"))

(= formatdoc-url* "formatdoc")

(= formatdoc* 
"Blank lines separate paragraphs.
<p> Text surrounded by dollar signs is rendered as LaTeX.
<p> Text after a blank line that is indented by two or more spaces is 
reproduced verbatim.  (This is intended for code.)
<p> Text surrounded by asterisks is italicized, if the character after the 
first asterisk isn't whitespace.
<p> A paragraph beginning with a hash mark (#) is a subheading.
<p> Urls become links, except in the text field of a submission.<br><br>")


; Noprocrast

(def check-procrast (user)
  (or (no user)
      (no (uvar user noprocrast))
      (let now (seconds)
        (unless (uvar user firstview)
          (reset-procrast user))
        (or (when (< (/ (- now (uvar user firstview)) 60)
                     (uvar user maxvisit))
              (= (uvar user lastview) now)
              (save-prof user)
              t)
            (when (> (/ (- now (uvar user lastview)) 60)
                     (uvar user minaway))
              (reset-procrast user)
              t)))))
                
(def reset-procrast (user)
  (= (uvar user lastview) (= (uvar user firstview) (seconds)))
  (save-prof user))

(def procrast-msg (user whence)
  (let m (+ 1 (trunc (- (uvar user minaway)
                        (minutes-since (uvar user lastview)))))
    (pr "<b>Get back to work!</b>")
    (para "Sorry, you can't see this page.  Based on the anti-procrastination
           parameters you set in your profile, you'll be able to use the site 
           again in " (plural m "minute") ".")
    (para "(If you got this message after submitting something, don't worry,
           the submission was processed.)")
    (para "To change your anti-procrastination settings, go to your profile 
           by clicking on your username.  If <tt>noprocrast</tt> is set to 
           <tt>yes</tt>, you'll be limited to sessions of <tt>maxvisit</tt>
           minutes, with <tt>minaway</tt> minutes between them.")
    (para)
    (w/rlink whence (underline (pr "retry")))
    ; (hspace 20)
    ; (w/rlink (do (reset-procrast user) whence) (underline (pr "override")))
    (br2)))


; Reset PW

(defopg resetpw req (resetpw-page (get-user req)))

(def resetpw-page (user (o msg))
  (minipage "Reset Password"
    (if msg
         (pr msg)
        (blank (uvar user email))
         (do (pr "Before you do this, please add your email address to your ")
             (underlink "profile" (user-url user))
             (pr ". Otherwise you could lose your account if you mistype 
                  your new password.")))
    (br2)
    (uform user req (try-resetpw user (arg req "p"))
      (single-input "New password: " 'p 20 "reset" t))))

(def try-resetpw (user newpw)
  (if (len< newpw 4)
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

