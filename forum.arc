; bug: somehow (+ votedir* nil) is getting evaluated.
;! (seconds) uses "platform-specific starting date" ?!

(declare 'atstrings t)

(= this-site*    "Intelligent Agent Foundations Forum"
   site-url*     "http://agentfoundations.org/" ; unfortunate, but necessary for rss feed
   parent-url*   ""
   favicon-url*  ""
   site-desc*    "Intelligent Agent Foundations Forum" ; for rss feed
   ; site-color*   (color 40 50 120) ; not even used
   border-color* (color 180 180 180)
   prefer-url*   t)

; -------------------------------- Structures -------------------------------- ;

; Could add (html) types like choice, yesno to profile fields.  But not 
; as part of deftem, which is defstruct.  Need another mac on top of 
; deftem.  Should not need the type specs in user-fields.

(deftem profile
  id         nil
  name       nil ; @2015-04-05 secure but may not stay so always
  created    (seconds)
  auth       0
  member     nil
  submitted  nil
  contributor-only nil
  karma      1
  weight     .5
  email      nil ; @2015-04-05 unused
  about      nil
  keys       nil
  delay      0)

(deftem item
  id           nil
  version      0     ; incremented before first save
  draft        nil
  type         nil
  category     nil   ; for stories: 'Main, 'Discussion, or 'Link
  by           nil
  ip           nil
  time         nil   ; set on save
  publish-time nil   ; set on first publish
  title        nil
  text         nil
  url          nil   ; for links (category 'Link) only
  deleted      nil
  parent       nil
  keys         nil)

; ------------------------------- Load and Save ------------------------------ ;

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

(def profile-file (u)
  (if (is u "János_Kramár")  "J?nos_Kram?r"
      (is u "Mihály_Bárász") "Mih?ly_B?r?sz"
                             u))

(def load-user (u)
  (= (votes* u) (load-table (+ votedir* (profile-file u)))
     (profs* u) (temload 'profile (+ profdir* (profile-file u))))
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

(def vote (user item) (votes.user item!id))

(def init-user (u)
  (= (votes* u) (table) 
     (profs* u) (inst 'profile 'id u 'contributor-only t))
  (save-votes u)
  (save-prof u)
  u)

; Need this because can create users on the server (for other apps)
; without setting up places to store their state as news users.
; See the admin op in app.arc.  So all calls to login-page from the 
; news app need to call this in the after-login fn.

(def ensure-news-user (u) (if (profile u) u (init-user u)))

(def save-votes (u) (save-table (votes* u) (+ votedir* u)))

(def save-prof  (u) (save-table (profs* u) (+ profdir* u)))

(mac uvar (u k) `((profile ,u) ',k))

(mac karma (u) `(uvar ,u karma))

(def full-member (u)
  (aand u (no ((profile u) 'contributor-only))))

; Note that users will now only consider currently loaded users.

(def users ((o f idfn)) (keep f (keys profs*)))

(def check-key (u k) (and u (mem k (uvar u keys))))

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
    (hook 'initload items)))

(def astory   (i) (and i (is i!type 'story)))
(def acomment (i) (and i (is i!type 'comment)))

(def load-item (id)
  (let i (temload 'item (newest-item-file id))
    (= (itemtext* id) (filechars:item-file id i!version "html"))
    (if i!parent (pushnew id (itemkids* i!parent)))
    ; Workaround for posts / comments that were published before
    ; publish-time code was added
    (if (and (no i!draft) (no i!publish-time))
        (= i!publish-time i!time))
    (if (and (is i!type 'story) (no i!category))
        (= i!category 'Main))
    (= (items* id) i)))

(= newuserid* 0)
(def new-user-id () (string (evtil (++ newuserid*) [no (profs* (string _))])))
(def new-item-id () (evtil (++ maxid*) [~file-exists (+ storydir* _ "v1")]))

(def item (id) (or (items* id) (errsafe:load-item id)))

(def kids (i) (map item (itemkids* i!id)))

; For use on external item references (from urls).  Checks id is int 
; because people try e.g. item?id=363/blank.php

(def safe-item (id) (ok-id&item (if (isa id 'string) (saferead id) id)))

(def ok-id (id) (and (exact id) (<= 1 id maxid*)))

(def arg->item (req key) (safe-item:saferead (arg req key)))

(def live (i) (no i!deleted))

(def save-item (i)
  (++ i!version)
  (let current-time (seconds)
    (= i!time current-time)
    (if (and (no i!draft) (no i!publish-time)) (= i!publish-time current-time)))
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

(def loaded-items (test) (accum a (each-loaded-item i (test&a i))))

(def newslog args (apply srvlog 'news args))

; ---------------------------------- ?misc? ---------------------------------- ;

(def user-age (u) (minutes-since (uvar u created)))
(def item-age (i) (if (no i!publish-time) (minutes-since i!time) (minutes-since i!publish-time)))

(def realscore (i) (+ 1 (len (itemlikes* i!id))))

; With virtual lists the call to latest-items could be simply: (map item (retrieve consider astory:item (gen maxid* [- _ 1])))
(def rank-stories (n consider scorefn) (bestn n (compare > scorefn) (latest-items astory nil consider)))
(def latest-items (test (o stop) (o n)) ; internal to rank-stories
  (accum a (catch (down id maxid* 1
    (let i (item id)
      (if (or (and stop (stop i)) (and n (<= n 0))) (throw))
      (when (test i) (a i) (if n (-- n))))))))

; -------------------------------- Permissions ------------------------------- ;

(= max-delay* 10)
(= canreply-threshold* 1)
(= invisible-threshold* 2)

; Assumes 'cansee' check is performed elsewhere
(def cancomment (user i)
  (if (astory i)
    (no (and
      (no (full-member i!by))
      (is i!category 'Link)
      (no (>= (len (itemlikes* i!id)) canreply-threshold*))
      ))
    (canreply user i)))

(def canreply (user i)
  (if (full-member i!by)
       t
      (or (full-member user) (author user i))
       (>= (len (itemlikes* i!id)) canreply-threshold*)
      t))

(def invisible (i)
  (and
    (no (full-member i!by))
    (< (len (itemlikes* i!id)) invisible-threshold*)))

(def cansee (user i)
  (if i!deleted (admin user)
      i!draft (author user i)
      (delayed i) (author user i)
      (no (full-member i!by)) (or
       (author user i)
       (full-member user)
       (>= (len (itemlikes* i!id)) invisible-threshold*)
       (and (no (is i (superparent i))) (author i!by (superparent i)) (cansee user (superparent i))))
      t))

(def cansee_d (user i) (and (cansee user i) (no i!draft)))

(let mature (table)
(def delayed (i)
  (and (no (mature i!id))
       (acomment i)
       (or (< (item-age i) (min max-delay* (uvar i!by delay)))
           (do (set (mature i!id))
               nil)))))

(def visible (user is (o hide-drafts))
  (keep [and (cansee user _) (or (no hide-drafts) (no _!draft))] is))

; unused by forum
; (def cansee-descendant (user c)
;   (or (cansee user c)
;       (some [cansee-descendant user _] (kids c))))
  
(def editor (u) (and u (or (admin u) (> (uvar u auth) 0))))
(def member (u) (and u (or (admin u) (uvar u member))))

; -------------------------------- Page Layout ------------------------------- ;

(= logo-url* "miri.png")
(= favicon-url* "favicon.png")
; (defopr favicon.ico req favicon-url*)

; redefined later

(def gen-css-url () (prn "<link rel=\"stylesheet\" type=\"text/css\" href=\"forum.css\">"))

; unused by forum
; (def rand-id () (round (* (rand) 1e16)))

(def gen-collapse-script (c identifier)
  (let template "<script>
    //! should probably be $(function(){
    $(window).load(function(){
      $('.toggle-{{1}}').click(function(){
        var was_expand = $(this).text().indexOf('[+]') === 0
        $('td.comment-{{1}}').css('display', was_expand? 'block' : 'none')
        $(this).text((was_expand? '[-] Collapse' : '[+] Expand')+' comment by {{2}}')
        return false }) })
    </script>"
    (multisubst `(("{{1}}" ,identifier) ("{{2}}" ,(get-user-display-name c!by))) template)))

(mac npage (notify title . body) ; alice@2015-03-16 note: 'notify gets ignored
  `(tag html 
     (tag head 
       (gen-css-url)
       (prn "<link rel=\"shortcut icon\" href=\"" favicon-url* "\">")
       (prn script-mathjax)
       (prn script-jquery)
       (prn "<script src='/jquery.cookie.js'></script>")
       (prn "<script>
         var t = location.href.replace(/^https?:\\/\\/malo-agentfoundations.terminal.com\\//,'http://agentfoundations.org/')
         if (location.href !== t) {
           if (!/user=/.test(location.search)) {
             var search_push = function(k,v){location.search += (location.search !== ''? '&' : '?')+k+'='+v}
             search_push('user', $.cookie('user'))
           } else {
             location.replace(t)
           }
         } else {
           if (/user=/.test(location.search)) {
             var t = location.search.match(/user=([^&]+)/)
             if (t && t[1] && $.cookie('user') !== t[1]) {
               $.cookie('user',t[1])
               location.reload()
             }
           }
         }
         </script>")
       (tag title (pr ,title)))
     (tag body
       (center
         ; (if ,notify
         ;   (tag (table class "notify")
         ;     (tr (td
         ;       (pr "Welcome to the Intelligent Agent Foundations Forum!  New users, please ")
         ;       (link "read this first" "welcome")
         ;       (pr ".")))))
         (tag (table class "frame")
           ,@body))
       (prn "<script>$(function(){if (/^\\/(news|newest|)$/.test(location.pathname)) $('body > center > table > tbody > tr:nth-child(2) > td > table > tbody > tr > td.contents > table > tbody').prepend(\"<tr><td><table width='100%' style='width: 100%; background-color: #eaeaea;'><tbody><tr style='height:5px'></tr><tr><td><img src='s.gif' height='1' width='14'></td></tr><tr><td colspan='1'></td><td class='story' width='100%' style='text-align:left; font-size: 12pt; color: 254e7d;'><p>This is a publicly visible discussion forum for foundational mathematical research in \\\"robust and beneficial\\\" artificial intelligence, as discussed in the Future of Life Institute's <a href='http://futureoflife.org/misc/open_letter' class='continue' style='text-decoration: underline;'>research priorities letter</a> and the Machine Intelligence Research Institute's <a href='https://intelligence.org/technical-agenda/' class='continue' style='text-decoration: underline;'>technical agenda</a>.</p><p>If you'd like to participate in the conversations here, see our <a href='/how-to-contribute' class='continue' style='text-decoration: underline;'>How to Contribute page »</a></p></td></tr><tr style='height:12px'></tr></tbody></table></td></tr><tr style='height:10px'></tr>\")})</script>")
       )))

(= pagefns* nil)

(mac fulltop (user lid label title whence . body) ; used by: longpage, shortpage
  (w/uniq (gu gi gl gt gw)
    `(with (,gu ,user ,gi ,lid ,gl ,label ,gt ,title ,gw ,whence)
       (npage nil (+ this-site* (if ,gt (+ bar* ,gt) "")) ; alice@2015-03-16 we don't care about user-ness
       ; (npage (no user) (+ this-site* (if ,gt (+ bar* ,gt) ""))
         (do (pagetop 'full ,gi ,gl ,gt ,gu ,gw)
             (hook 'page ,gu ,gl)
             ,@body)))))

(mac format-sb-title (title) `(para (tag (h3) (pr ,title)))) ; internal to longpage-sb
(mac format-sb-item (i) `(do (pr ; internal to longpage-sb
  "<div style='margin: 1em 0;'>"
    "<a href='"(if (is i!category 'Link) i!url (item-url i!id))"' class='"(if (invisible i) 'sb-invisible 'sb)"'>"
      "<b>"(eschtml i!title)"</b></a>"
    "<br>"
    "<div class='"(if (invisible i) 'sb-invisible-subtext 'sb-subtext)"' style='margin:3px;'>"
      ;! (commentlink i nil) instead of (commentlink i user) may display the wrong number of comments
      "by ") (userlink user i!by) (pr bar*) (itemscore i) (if (is i!category 'Link) (commentlink nil i)) (pr "</div></div>")))
(mac add-sidebar (sidebar-contents . body) ; internal to longpage-sb
  `(tag (table style 'border-collapse:collapse width '100%)
        (tr (tag (td valign 'top class 'contents) ,@body)
            (tag (td valign 'top class 'sb) ,sidebar-contents))))
(mac longpage (user t1 lid label title whence . body) ; internal to longpage-sb
  (w/uniq (gu gt gi)
    `(with (,gu ,user ,gt ,t1 ,gi ,lid)
      (fulltop ,gu ,gi ,label ,title ,whence
        (trtd ,@body)
        (trtd 
          (center
            (hook 'longfoot)
            (admin-bar ,gu (- (msec) ,gt) ,whence)))
        )
        (pr "<center><div class='sb' style='margin: 3px 0;'><a title='Read our Privacy Policy' href='https://intelligence.org/files/PrivacyandTerms-Agentfoundations.org.pdf'>Privacy &amp; Terms <font color='red' size='2'><strong>(NEW 04/01/15)</strong></font></a></div></center>")
        )))
(mac longpage-sb (user t1 lid label title whence show-comments . body)
  `(longpage ,user ,t1 ,lid ,label ,title ,whence
     (if (no ,show-comments) 
       (do ,@body)
       (add-sidebar (+
         (format-sb-title (link "NEW LINKS" "links"))
         (each i (sb-links ,user sb-link-count*) (format-sb-item i))
         (format-sb-title "NEW POSTS")
         (each i (sb-posts ,user sb-post-count*) (format-sb-item i))
         (format-sb-title "NEW DISCUSSION POSTS")
         (each i (sb-discussion-posts ,user sb-discussion-post-count*) (format-sb-item i))
         (format-sb-title (link "RECENT COMMENTS" "newcomments"))
         (each c (sb-comments ,user sb-comment-count*)
           (tag (p) (tag (a href (item-url c!id) class 'sb)
                      (tag (b) (pr (eschtml (shortened c!text sb-comment-maxlen*)))))
                    (br)
                    (tab (tr (tag (td class 'sb-subtext)
                      (pr "by ")
                      (userlink user c!by)
                      (pr " on ")
                      (let s (superparent c)
                        (pr (ellipsize s!title 50)))
                      (pr bar*)
                      (itemscore c))))))
         (format-sb-title (link "RSS" "rss")))
         ,@body))))

(def reverse (text) (coerce (rev (coerce text 'cons)) 'string))

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
      (link "settings" "forum-admin")
      (hook 'admin-bar user whence))))

(def color-stripe (c)
  (tag (table width "100%" cellspacing 0 cellpadding 1)
    (tr (tdcolor c))))

(mac shortpage (user lid label title whence . body)
  `(fulltop ,user ,lid ,label ,title ,whence 
     (trtd ,@body)))

(mac minipage (label . body)
  `(npage nil (+ this-site* bar* ,label)
     (pagetop nil nil ,label)
     (trtd ,@body)))

(def msgpage (user msg (o title))
  (minipage (or title "Message")
    (spanclass admin
      (center (if (len> msg 80) 
                  (widtable 500 msg)
                  (pr msg))))
    (br2)))

(= (max-age* 'forum.css) 60)   ; cache css in browser for 1 minute

; turn off server caching via (= caching* 0) or won't see changes
(= caching* 0)

(defop forum.css req (pr "
  /* forum.css generated version 1.2 */

  body {
  background: #eaeaea;
  background-color:#eaeaea !important;
  margin: 0px;
  }

  table.notify
  {
  width: 100%; background-color: #eaeaea;
  padding: 5px; text-align: center;
  }

  .notify td {
      font-size: 12pt;
      color: 254e7d;
  }

  .notify a:link {
      text-decoration: underline;
  }

  table.frame
  {
  width: 85%; border-left: 1px solid #d2d2d2;
  border-right: 1px solid #d2d2d2; background-color: #ffffff;
  -webkit-border-horizontal-spacing: 0px;
  -webkit-border-vertical-spacing: 0px;
  }


  table.topbar {
  width: 100%;
  padding: 2px;
  background-color: #254e7d;
  }
  .pagetop a:visited {
  color:#ffffff; 
  }

  /*
   * begin dropdown menu css
   */

  ul.dropdown {
    text-align: left;
    display: inline;
    margin: 0;
    padding: 0 0 0 0;
    list-style: none;
  }

  ul.dropdown li {
    display: inline-block;
    position: relative;
    padding: 5px 0px;
    background: #254e7d;
  }

  ul.dropdown li ul {
    padding: 0;
    position: absolute;
    top: 25px;
    left: -4px;
    width: 125px;
    box-shadow: none;
    display: none;
    opacity: 0;
    visibility: hidden;
  }

  ul.dropdown li ul li {
    display: block;
    padding: 5px 4px;
  }

  ul.dropdown li:hover ul {
    display: block;
    opacity: 1;
    visibility: visible;
  }

  /*
   * end dropdown menu css
   */

  table td.sb {
  background-color: #f8f8f8;
  width: 300px;
  padding: 8px;
  font-size: 10pt;
  }

  table td.sb > h3 {
  font-family: Verdana;
  font-size: 12pt;
  font-weight: bold;
  color: #92b437 !important;
  }

  table td.sb > h3 > a:link {
  font-family: Verdana;
  font-size: 12pt;
  font-weight: bold;
  color: #92b437;
  }

  table td.sb > h3 > a:visited {
  font-family: Verdana;
  font-size: 12pt;
  font-weight: bold;
  color: #92b437;
  }

  a:visited {
  color: #000000;
  }

  td    { font-family:Verdana; font-size:13pt; color:#000000; }

  hr       { border:0; text-align:center; }
  hr:after { content:\"*\"; }

  td > h1 { font-family:Verdana; font-size:14pt; color:#000000; font-weight:bold; }

  img.logo { width:26; height:18; border:0px #@(hexrep border-color*) solid;}

  table.mainsite { width:100%; cellpadding:0; cellspacing:0; border:0; padding:0px; }
  table tr.header   { background-color:#283278; font-color:#ffffff; font-weight:bold; border-radius:15px; }
  table td.contents { margin:0; padding-right:80; }
  table td.story    { line-height:135%; }

  .admin td   { font-family:Verdana; font-size:10.5pt; color:#000000; }
  .subtext td { font-family:Verdana; font-size:  10pt; color:#828282; }
  .subtext-invisible td { font-family:Verdana; font-size:  10pt; color:#bbbbbb; }

  table td.sb > p { font-family:Verdana; font-size:10pt; font-weight:regular; color:#ffffff;}

  button   { font-family:Verdana; font-size:11pt; color:#000000; }
  input    { font-family:Courier; font-size:13pt; color:#000000; }
  input[type=\"submit\"] { font-family:Verdana; }
  textarea { font-family:Courier; font-size:13pt; color:#000000; }

  a:link    { color:#000000; text-decoration:none; } 

  .default     { font-family:Verdana; font-size:  13pt; color:#828282; }
  .admin       { font-family:Verdana; font-size:10.5pt; color:#000000; }
  .title       { font-family:Verdana; font-size:  16pt; color:#828282; font-weight:bold; }
  .discussion-title { font-family:Verdana; font-size:13pt; color:#828282; font-weight:bold; }
  .adtitle     { font-family:Verdana; font-size:  11pt; color:#828282; }
  .subtext     { font-family:Verdana; font-size:  10pt; color:#828282; }
  .subtext-invisible { font-family:Verdana; font-size: 10pt; color:#bbbbbb; }
  .sb-subtext  { font-family:Verdana; font-size:   8pt; color:#828282; }
  .sb-invisible-subtext  { font-family:Verdana; font-size: 8pt; color:#bbbbbb; }
  .yclinks     { font-family:Verdana; font-size:  10pt; color:#828282; }
  .pagetop     { font-family:Verdana; font-size:  11pt; color:#ffffff; }
  .comhead     { font-family:Verdana; font-size:  10pt; color:#828282; }
  .comment     { font-family:Verdana; font-size:  12pt; color:#000000; }
  .dead        { font-family:Verdana; font-size:  11pt; color:#dddddd; }

  .userlink, .you { font-weight:bold; }

  .comment a:link, .comment a:visited, .story a:link, .story a:visited { text-decoration:underline; }
  .dead a:link, .dead a:visited { color:#dddddd; }
  .pagetop a:link { color:#ffffff; }
  .pagetop a:visited { color:#ffffff; }
  .topsel, .topsel a:link, .topsel a:visited { color:#ffc040; }

  .subtext a:link, .subtext a:visited { color:#828282; }
  .subtext a:hover { text-decoration:underline; }

  .subtext-invisible a:link, .subtext-invisible a:visited { color:#bbbbbb; }
  .subtext-invisible a:hover { text-decoration:underline; }

  .sb a:link, .sb a:visited { color:#828282; }
  .sb a:hover { text-decoration:underline; }

  a.sb-invisible:link, a.sb-invisible:visited { color:#bbbbbb; }
  .sb-invisible-subtext a:link, .sb-invisible-subtext a:visited {color:#bbbbbb; }

  .comhead a:link, .subtext a:visited { color:#828282; }
  .comhead a:hover { text-decoration:underline; }

  .continue a:link, .subtext a:visited { color:#828282; text-decoration:underline; }
  .doclink a:link { font-weight:bold; text-decoration:underline; }

  .default p { margin-top: 8px; margin-bottom: 0px; }

  .example-raw      { margin:20px; background-color:white; }
  .example-rendered { margin:20px; }

  .pagebreak {page-break-before:always}

  pre { overflow: auto; padding: 2px; max-width:600px; }
  pre:hover {overflow:auto}
  "))

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

; --------------------------------- Page top --------------------------------- ;

(= sand (color 240 246 255) textgray (gray 130))

(def pagetop (switch lid label (o title) (o user) (o whence))
  (tr (td
        (tag (table class "topbar")
          (tr (gen-logo)
              (when (is switch 'full)
                (tag (td style "line-height:12pt; height:10px;")
                  (spanclass pagetop
                    (tag b (link this-site* "/"))
                    (hspace 10)
                    (toprow user label))))
             (if (is switch 'full)
                 (tag (td style "text-align:right;padding-right:4px;")
                   (spanclass pagetop (topright user whence)))
                 (tag (td style "line-height:12pt; height:10px;")
                   (spanclass pagetop (prbold label))))))))
  (map [_ user] pagefns*)
  )

(def gen-logo ()
  (tag (td style "width:18px;padding-right:4px")
    (tag (a href parent-url*)
      (tag (img class "logo" src logo-url* )))))

(= toplabels* '(nil "new" "comments" "links" "full members" "contributors"
                    "my posts" "my comments" "my drafts" "my likes" "*"))

; redefined later

(def toprow (user label)
  (tag (ul class 'dropdown)
    (w/bars
      (toplink "new" "/" label)
      (toplink "comments" "newcomments" label)
      (toplink "links" "links" label)
      (tag li
        (tag-if (or
                  (is label "full members")
                  (is label "contributors"))
                (span class 'topsel)
          (pr "members"))
        (tag ul
          (toplink "full members" "members" label)
          (toplink "contributors" "contributors" label)))
      (when user
        (tag li
          (tag-if (and label (headmatch "my " label)) (span class 'topsel)
            (pr "my content"))
          (tag ul
            (toplink "my posts" (submitted-url user) label)
            (toplink "my comments" (threads-url user) label)
            (toplink "my drafts" "drafts" label)
            (toplink "my likes" (saved-url user) label))))
      (hook 'toprow user label)
      (tag li (link "submit"))
      (unless (mem label toplabels*)
        (tag li (fontcolor white (pr label)))))))

(def toplink (name dest label)
  (tag li
    (tag-if (is name label) (span class 'topsel)
      (link name dest))))

(def topright (user whence (o showkarma t))
  (if user (do
    (userlink user user)
    (when showkarma (pr  "&nbsp;(@(* karma-multiplier* (karma user)))"))
    (pr "&nbsp;|&nbsp;")
    (rlinkf 'logout (req)
      (when-umatch/r user req
        (logout-user user)
        whence))
  ) (do
    (onlink "sign up / log in"
      (login-page 'login+fb nil
        (list (fn (u ip) (ensure-news-user u) (newslog ip u 'top-login)) whence)
        ))
  )))

; ----------------------- News-Specific Defop Variants ----------------------- ;

(mac defopt (name parm test msg . body)
  `(defop ,name ,parm
     (if (,test (get-user ,parm))
         (do ,@body)
         (login-page 'login+fb (+ "Please log in" ,msg ".")
                     (list (fn (u ip) (ensure-news-user u))
                           (string ',name (reassemble-args ,parm)))))))

(mac defopg (name parm . body) `(defopt ,name ,parm idfn "" ,@body))
(mac defope (name parm . body) `(defopt ,name ,parm editor " as an editor" ,@body))
(mac defopa (name parm . body) `(defopt ,name ,parm admin " as an administrator" ,@body))

(mac opexpand (definer name parms . body)
  (w/uniq gr
    `(,definer ,name ,gr
       (with (user (get-user ,gr) ip (,gr 'ip))
         (with ,(and parms (mappend [list _ (list 'arg gr (string _))]
                                    parms))
           (newslog ip user ',name ,@parms)
           ,@body)))))

(= newsop-names* nil)

(mac newsop args `(do (pushnew ',(car args) newsop-names*) (opexpand defop ,@args)))

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

; -------------------------------- News Admin -------------------------------- ;

(defopa forum-admin req 
  (let user (get-user req)
    (newslog req!ip user 'forumadmin)
    (forumadmin-page user)))

; Note that caching* is reset to val in source when restart server.

(def nad-fields ()
  `((num      caching         ,caching*                       t t)))

; Need a util like vars-form for a collection of variables.
; Or could generalize vars-form to think of places (in the setf sense).

(def forumadmin-page (user)
  (shortpage user nil nil "forum-admin" "forum-admin"
    (para (onlink "Create Account" (admin-page user)))
    (vars-form user 
               (nad-fields)
               (fn (name val)
                 (case name
                   caching            (= caching* val)
                   ))
               (fn () (forumadmin-page user)))))


(newsop how-to-contribute ()
  (longpage-sb user (msec) nil nil "How to contribute" "how-to-contribute" t
    (pr "<div class='story' style='padding:20px;'>")
    (pr "
      <h2 style='margin-top:0;'>How to contribute</h2>
      This is a publicly visible discussion forum for foundational mathematical research in artificial intelligence. The goal of this forum is to move toward a more formal and general understanding of \"robust and beneficial\" AI systems, as discussed in the Future of Life Institute's <a href='http://futureoflife.org/misc/open_letter'>research priorities letter</a> and the Machine Intelligence Research Institute's <a href='https://intelligence.org/technical-agenda/'>technical agenda</a>.
      <br><br>
      Like <a href='http://mathoverflow.net/help/privileges'>Math Overflow</a>, the Intelligent Agent Foundations Forum has a tiered system for becoming a member. If you make an account with a Facebook login, you can contribute comments and links, e.g. to an external post on <a href='http://medium.com/'>Medium.com</a> or on a personal blog. These comments and links will initially be visible to forum members; if your contribution acquires a few Likes from members, it will become visible to all site visitors.
      <br><br>
      If you frequently link to some good original content that you have written, the administrators will invite you to become a full member. The details of this system are still being worked out, and will change as we get a larger community of users.
      <br><br>
      <h2 style='margin-top:0;'>What are the main topics of this forum?</h2>
      Broadly speaking, the topics of this forum concern the difficulties of value alignment- the problem of how to ensure that machine intelligences of various levels adequately understand and pursue the goals that their developers actually intended, rather than getting stuck on some proxy for the real goal or failing in other unexpected (and possibly dangerous) ways. As these failure modes are more devastating the farther we advance in building machine intelligences, MIRI’s goal is to work today on the foundations of goal systems and architectures that would work even when the machine intelligence has general creative problem-solving ability beyond that of its developers, and has the ability to modify itself or build successors.
      <br><br>
      In that context, there are many interesting problems that come up. Here is a non-exhaustive list of relevant topics:
      <ul>
        <li style='margin-top: .5em;'><b>Decision theory:</b> One class of topics comes from the distortions that arise when an agent predicts its environment, including its own future actions or the predictions of other agents, and tries to make decisions based on those. The tools of classical game theory and decision theory begin to make substandard recommendations on Newcomblike problems, blackmail problems, and other topics in this domain, and formal models of decision theories have brought up entirely unexpected self-referential failure modes. This has spurred the development of some new mathematical models of decision theory and counterfactual reasoning. (<a href='https://intelligence.org/files/TowardIdealizedDecisionTheory.pdf'>MIRI research agenda paper on decision theory</a>)</li>
        <li style='margin-top: .5em;'><b>Logical uncertainty:</b> In the classical formalism of Bayesian agents, the agent updates on new evidence in a way that makes use of all logical consequences. In any interesting universe (even, say, the theory of arithmetic), this is actually an impossible assumption. Any bounded reasoner must have a satisfactory way of dealing with hypotheses that may in fact be determined from the data, but which have not yet been deduced either way. There are some interesting and analogous models of coherent (or locally coherent) probability distributions on the theory of arithmetic. (<a href='https://intelligence.org/files/QuestionsLogicalUncertainty.pdf'>MIRI research agenda paper on logical uncertainty</a>)</li>
        <li style='margin-top: .5em;'><b>Reflective world-models:</b> The distinction between an agent and its environment is a fuzzy one. Performing an action in the environment (e.g. sabotaging one’s own hardware) can predictably affect the agent’s future inferential processes. Furthermore, there are some models of intelligence and learning in which the correct hypotheses about the agent itself are not accessible to the agent. In both cases, there has been some progress on building mathematical models of systems that represent themselves more sensibly. (<a href='https://intelligence.org/files/RealisticWorldModels.pdf'>MIRI research paper on reflective world-models</a>)</li>
        <li style='margin-top: .5em;'><b>Corrigibility:</b> Many goal systems, if they can reason reflectively and strategically, will seek to preserve themselves (because otherwise, their current goal state will be less likely to be reached). This gives rise to a potential problem with communicating human value to a machine intelligence: if the developers make a mistake in doing so, the machine intelligence may seek ways to avoid being corrected. There are several models of this, and a few proposals. (<a href='https://intelligence.org/files/Corrigibility.pdf'>MIRI research paper on corrigibility</a>)</li>
        <li style='margin-top: .5em;'><b>Self-trust and Vingean reflection:</b> Informally, if an agent self-modifies to become better at problem-solving or inference, it should be able to trust that its modified self will be better at achieving its goals. As it turns out, there is a self-referential obstacle with simple models of this (akin to the fact that only inconsistent formal systems believe themselves to be consistent), and one method of fixing it results in the possibility of indefinitely deferred actions or deductions. (<a href='https://intelligence.org/files/VingeanReflection.pdf'>MIRI research paper on Vingean reflection</a>)</li>
        <li style='margin-top: .5em;'><b>Value Learning:</b> Since human beings have not succeeded at specifying human values (citation: look at the lack of total philosophical consensus on ethics), we may in fact need the help of a machine intelligence itself to specify the values to a machine intelligence. This sort of “indirect normativity” presents its own interesting challenges. (<a href='https://intelligence.org/files/ValueLearningProblem.pdf'>MIRI research paper on value learning</a>)</li>
      </ul>
      Again, this list is not exhaustive! Besides the topics mentioned there, other relevant subjects for this forum include groundwork for self-modifying agents, abstract properties of goal systems, tractable theoretical or computational models of the topics above, and anything else that is directly connected to MIRI’s research mission.
      <br><br>
      It’s important for us to keep the forum focused, though; there are other good places to talk about subjects that are more indirectly related to MIRI’s research, and the moderators here may close down discussions on subjects that aren’t a good fit for this forum. Some examples of subjects that we would consider off-topic (unless directly applied to a more relevant area) include general advances in artificial intelligence and machine learning, general mathematical logic, general philosophy of mind, general futurism, existential risks, effective altruism, human rationality, and non-technical philosophizing.
      <br><br>
      <h2 style='margin-top:0;'>Contact Us</h2>
      You can reach us at <a href='mailto:forum&#64;intelligence.org'>forum&#64;intelligence.org</a> with any questions.
      <br><br>
      Thanks for reading, and we look forward to your contributions to this forum!
      ")
    (pr "</div>")
    ))

; ----------------------------------- Users ---------------------------------- ;

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
      (yesno   contributor-only ,(p 'contributor-only)             ,a  ,a)
      (posint  karma      ,(* karma-multiplier* (p 'karma))         t  ,a)
      (num     weight     ,(p 'weight)                             ,a  ,a)
      (pandoc  about      ,(p 'about)                               t  ,u)
      (string  email      ,(p 'email)                              ,u  ,u)
      (sexpr   keys       ,(p 'keys)                               ,a  ,a)
      (int     delay      ,(p 'delay)                              ,u  ,u))))

(def saved-link (user subject)
  (let n (if (len> (votes subject) 500) 
             "many" 
             (len (liked-stories user subject)))
    (tostring (underlink (+ (string n) " liked " (if (is n 1) "story" "stories"))
                         (saved-url subject)))))

(def resetpw-link () (tostring (underlink "reset password" "resetpw")))

; ------------------------------ Main Operators ------------------------------ ;

; remember to set caching to 0 when testing non-logged-in 

(= caching* 1 perpage* 25 threads-perpage* 10 maxend* 500
   preview-maxlen* 1000 karma-multiplier* 5)

(= sb-link-count* 5
   sb-post-count* 5
   sb-discussion-post-count* 5
   sb-comment-count* 15
   sb-comment-maxlen* 30)

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


(newsop ||   () (newestpage user))
(newsop news () (newestpage user)) ; deprecated link
(newsop newest () (newestpage user)) ; deprecated link

(def sb-links (user n) (retrieve n [and (cansee_d user _) (is _!category 'Link)] stories*))

(def sb-posts (user n) (retrieve n [and (cansee_d user _) (is _!category 'Main)] stories*))

(def sb-discussion-posts (user n) (retrieve n [and (cansee_d user _) (is _!category 'Discussion)] stories*))

(def sb-comments (user n) (retrieve n [and (cansee_d user _)] comments*))

(def listpage (user t1 items label title (o url label) (o number t) (o show-comments t) (o preview-only t) (o show-immediate-parent))
  (hook 'listpage user)
  (longpage-sb user t1 nil label title url show-comments
    (display-items user items label title url 0 perpage* number preview-only show-immediate-parent)))

; Note: deleted items will persist for the remaining life of the 
; cached page.  If this were a prob, could make deletion clear caches.

(newsop links () (linkspage user))

(newscache linkspage user 40
  (listpage user (msec) (newlinks user maxend*) "links" "New Links" "links"
            nil t))

(def newlinks (user n) (retrieve n [and (cansee_d user _) (is _!category 'Link)] stories*))

(newscache newestpage user 40
  (listpage user (msec) (newstories user maxend*) "new" "New Stories" "/" nil t))

(def newstories (user n)
  (retrieve n [and (cansee_d user _) (no (is _!category 'Link))] stories*))


(newsop best () (bestpage user))

(newscache bestpage user 1000 (listpage user (msec) (beststories user maxend*) "best" "Top Stories"))

; As no of stories gets huge, could test visibility in fn sent to best.

(def beststories (user n) (bestn n (compare > realscore) (visible user stories*)))


(newsop bestcomments () (bestcpage user))

(newscache bestcpage user 1000
  (listpage user (msec) (bestcomments user maxend*) "best comments" "Best Comments" "bestcomments" nil))

(def bestcomments (user n) (bestn n (compare > realscore) (visible user comments*)))


(newsop lists () 
  (longpage-sb user (msec) nil "lists" "Lists" "lists" t
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

(newsop drafts ()
  (if user (draftspage user)
    (login-page 'login+fb "You have to be logged in to view your drafts."
                (fn (user ip)
                  (ensure-news-user user)
                  (newslog ip user 'submit-login)
                  (draftspage user)))))

(def draftspage (user)
  (listpage user (msec) (drafts user) "my drafts" "My Drafts" "drafts" nil t t t))

(def drafts (user) (keep [and (cansee user _) _!draft] (submissions user)))

; ------------------------------- Story Display ------------------------------ ;

(def display-items (user items label title whence 
                    (o start 0) (o end perpage*) (o number) (o preview-only) (o show-immediate-parent))
  (tag (table width '100%)
    (let n start
      (each i (cut items start end)
        (trtd (tag (table width '100%)
                (display-item (and number (++ n)) i user whence t preview-only show-immediate-parent)
                (spacerow (if (is i!category 'Main) 25 5))))))
    (spacerow 10)
    (tr (tag (td align 'right)
      (w/bars
        (when (< 0 start)
          (let newstart (max 0 (- start perpage*))
            (navlink "Newer" display-items
                    items label title newstart start number t)))
        (when end
          (let newend (+ end perpage*)
            (when (and (<= newend maxend*) (< end (len items)))
              (navlink "Older" display-items
                      items label title end newend number t)))))))))

; This code is inevitably complex because the More fn needs to know 
; its own fnid in order to supply a correct whence arg to stuff on 
; the page it generates, like logout and delete links.

(def navlink (name f items label title . args)
  (tag (a href 
          (url-for
            (afnid (fn (req)
                     (prn)
                     (with (url  (url-for it)     ; it bound by afnid
                            user (get-user req))
                       (newslog req!ip user 'more label)
                       (longpage-sb user (msec) nil label title url t
                         (apply f user items label title url args))))))
          rel 'nofollow)
    (pr name)))

(def display-story (i s user whence preview-only (o commentpage))
  (when (or (cansee user s) (itemkids* s!id))
    (tr (when (no commentpage)
          (td (votelinks-space))
          (display-item-number i))
        (titleline s user whence))
    (tr (when (no commentpage)
          (tag (td colspan (if i 2 1))))
        (tag (td class (if (invisible s) 'subtext-invisible 'subtext))
          (hook 'itemline s user)
          (itemline s user whence)
          (when (astory s) (when (cansee_d user s) (commentlink user s)))
          (editlink s user)
          (deletelink s user whence)))
    (spacerow 10)
    (tr (when (no commentpage)
          (tag (td colspan (if i 2 1))))
        (tag (td class 'story width '100%)
          (let displayed (display-item-text s user preview-only)
            (pr displayed)
            (if (and preview-only
                     (is s!category 'Main)
                     (no (is displayed (item-text s))))
              (tag (table class 'mainsite)
                (tr (tag (td class 'continue)
                  (link "continue reading &raquo;" (item-url s!id)))))))))))

(def display-item-number (i)
  (when i (tag (td align 'right valign 'top class 'title)
            (pr i "."))))

; TODO: add a td class for the 'Link category?
(def titleline (s user whence)
  (tag (td class (if (is s!category 'Main) 'title
                     (or (is s!category 'Discussion) (is s!category 'Link)) 'discussion-title))
    (if (cansee user s)
        (do (deadmark s user)
            (if s!draft (tag (a href (item-url s!id)
                                style 'font-style:italic)
                          (pr (+ "[draft] " s!title)))
                (if (is s!category 'Link)
                  (if (invisible s) (tag (a href s!url style 'color:#bbbbbb) (pr s!title)) (link s!title s!url))
                  (link s!title (item-url s!id)))))
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
       (full-member user)
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
         whence (if whence (urldecode whence) "/"))
    (if (no i)
         (pr "No such item.")
        (no (in dir 'like nil))
         (pr "Can't make that vote.")
        (is dir (vote user i))
         (pr "Already voted that way.")
        (and by (or (isnt by user) (isnt (sym auth) (user->cookie* user))))
         (pr "User mismatch.")
        (no user)
         (login-page 'login+fb "You have to be logged in as a full member to vote."
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
    (if (is i!category 'Discussion) (pr " discussion post")
        (is i!category 'Link) (pr " link")
        (is i!type 'story) (pr " post"))
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

(def byline (i user) (pr " by @(tostring (userlink user i!by)) @(text-age:item-age i) "))

(def get-user-display-name (userid)
  (let t (uvar userid name) (if (blank t) (subst " " "_" userid) t)))

(def user-url (user) (+ "user?id=" user))

(def userlink (user subject) ; user: authenticated user, subject: target user id
  (clink userlink (get-user-display-name subject) (user-url subject)))

(def userlink-or-you (user subject)
  (if (is user subject) (spanclass you (pr "You")) (userlink user subject)))

(def commentlink (user i)
  (pr bar*)
  (tag (a href (+ (item-url i!id) "#comments"))
    (let n (- (visible-family user i) 1)
      (if (> n 0)
          (pr (plural n "comment"))
          (pr "discuss")))))

(def visible-family (user i)
  (+ (if (cansee_d user i) 1 0)
     (sum [visible-family user (item _)] (itemkids* i!id))))

;(= user-changetime* 120 editor-changetime* 1440)

(= everchange* (table) noedit* (table))

(def canedit (user i)
  (or (admin user)
      (and (~noedit* i!type)
           (editor user))
           ;(< (item-age i) editor-changetime*))
      (own-changeable-item user i)))

(def own-changeable-item (user i) (and (author user i) (no i!deleted)))
  ; not used but may want to use in the future: (and
  ; (~mem 'locked i!keys)
  ; (or (everchange* i!type)
  ;     (< (item-age i) user-changetime*))))

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

; ---------------------------------- Voting ---------------------------------- ;

(def vote-for (user i (o dir 'like))
  (unless (or (is (vote user i) dir)
              (author user i)
              (~live i))
    (++ (karma i!by) (case dir like 1 nil -1))
    (save-prof i!by)
    (wipe (comment-cache* i!id))
    (if (is dir 'like) (pushnew user (itemlikes* i!id))
                       (zap [rem user _] (itemlikes* i!id)))
    (= ((votes* user) i!id) dir)
    (save-votes user)))

; ----------------------------- Story Submission ----------------------------- ;

(newsop submit ()
  (if user
      (submit-page user)
      (login-page 'login+fb "You have to be logged in to submit."
                  (fn (user ip)
                    (ensure-news-user user)
                    (newslog ip user 'submit-login)
                    (submit-page user)))))

(defop dosubmit req
  (with (user (get-user req)
         url (readvar 'url (or (arg req "url") "") "") ;! hacky use of readvar as a quick security patch
         title (striptags (or (arg req "title") ""))
         text (or (arg req "text") "")
         draft (isnt (arg req "draft") nil)
         category (if (is (arg req "category") "Main") 'Main
                      (is (arg req "category") "Discussion") 'Discussion
                      'Link))
    (if (~arg req "auth")
         (pr "Nothing here.")
        (and (no (full-member user)) (no (is category 'Link)))
         (pr "Contributors can only submit links.")
        (and (is category 'Link) (isnt draft nil))
         (submit-page user url title text category nolinkdraft*)
        (~check-auth req)
         (authentication-failure-msg req)
        (or (blank title) (and (is category 'Link) (blank url)))
         (submit-page user url title text category blankurl*)
        (or (blank title) (and (no (is category 'Link)) (blank text)))
         (submit-page user url title text category blanktext*)
        (len> title title-limit*)
         (submit-page user url title text category toolong*)
      (atlet s (create-story title url text user req!ip category draft)
        (submit-item user s)
        (if draft (edit-page user s)
            (is category 'Link) (pr "<meta http-equiv='refresh' content='0; url=/links'>")
            (pr "<meta http-equiv='refresh' content='0; url=/'>"))))))

(def submit-page (user (o url "") (o title "") (o text "") (o category) (o msg))
  (shortpage user nil nil "Submit" "submit"
    (pagemessage msg)
    (pr "<script>$(function(){if ($('[name=category]').length) {
      var t = function(){
        var t = $('[name=category]').val() === 'Link'
        ;(t? $('[name=text]') : $('[name=url]')).closest('tr').hide()
        ;(t? $('[name=url]') : $('[name=text]')).closest('tr').show()
        }
      $('[name=category]').change(t)
      t()
      }})</script>")
    (authform "/dosubmit" user
      (tab
        (row "title"    (input "title" title 50))
        (if (full-member user)
          (row "category" (do (menu "category" '(Main Discussion Link) (or category 'Main))
                              (pr " &nbsp; ")
                              (underlink "What's this?" "/item?id=52"))))
        (tr
          (td "url")
          (td (input "url" url 50)))
        (if (full-member user)
          (tr
            (td "text")
            (td
              (textarea "text" 16 50 (only.pr text))
              (pr " ")
              (tag (font size -2)
                (tag (a href formatdoc-url* target '_blank)
                  (tag (font color (gray 175)) (pr "formatting help")))))))
        (row "" (if (full-member user)
                  (do
                    (tag (button type 'submit
                                 name "draft"
                                 value "t"
                                 onclick "needToConfirm = false;")
                      (pr "save draft & preview"))
                    (protected-submit "publish post"))
                  (protected-submit "submit link")))))))

(= title-limit* 160
   retry*       "Please try again."
   toolong*     "Please make title < @title-limit* characters."
   blanktext*   "Please fill in the title and the body."
   blankurl*    "Please fill in the title and the URL."
   nolinkdraft* "Link submissions cannot be saved as drafts.")
(def submit-item (user i) (push i!id (uvar user submitted)) (save-prof user))

(def create-story (title url text user ip category draft)
  (newslog ip user 'create (list title))
  (if (is category 'Link) (= text "")
      (= url ""))
  (if (and url (no (begins url "http"))) (= url (+ "http://" url)))
  (let s (inst 'item 'type 'story 'id (new-item-id) 'category category
                     'title title 'url url 'text text 'by user 'ip ip 'draft draft)
    (save-item s)
    (= (items* s!id) s)
    (push s stories*)
    s))

; ------------- Individual Item Page (= Comments Page of Stories) ------------ ;

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

(def news-type (i) (and i (in i!type 'story 'comment)))

(def item-page (user i)
  (with (title (and (cansee user i)
                    (+ (if i!draft "[draft] " "")
                       (or i!title (aand (item-text i)
                                         (ellipsize (striptags it))))))
         here (item-url i!id))
    (longpage-sb user (msec) nil nil title here t
      (tab (display-item nil i user here)
           (when (and (cansee_d user i) (comments-active i))
             (spacerow 10)
             (row "" (comment-form i user here))))
      (br2) 
      (when (and (itemkids* i!id) (commentable i))
        (tag (a name "comments"))
        (tab (display-subcomments i user here))
        (br2)))))

(def commentable (i) (in i!type 'story 'comment))

; By default the ability to comment on an item is turned off after 45 days, but this can be overriden with commentable key.
; (= commentable-threshold* (* 60 24 45)) ; removed for now but may revisit later
(def comments-active (i)
  (and (live&commentable i)
       (live (superparent i))))
       ;(or (< (item-age i) commentable-threshold*)
       ;    (mem 'commentable i!keys))))

(= displayfn* (table))

(= (displayfn* 'story)   (fn (n i user here inlist preview-only show-immediate-parent)
                           (display-story n i user here preview-only)))

(= (displayfn* 'comment) (fn (n i user here inlist preview-only show-immediate-parent)
                           (display-comment n i user here nil 0 nil inlist show-immediate-parent)))

(def display-item (n i user here (o inlist) (o preview-only) (o show-immediate-parent))
  ((displayfn* (i 'type)) n i user here inlist preview-only show-immediate-parent))

(def superparent (i) (aif i!parent (superparent:item it) i))

(def until-token (text token) (let idx (posmatch token text) (if (no idx) text (cut text 0 idx))))

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
  (if
    (no (cansee user s)) nil
    (is s!category 'Main) (if
                            preview-only (preview (item-text s))
                            (item-text s))
    (is s!category 'Discussion) (if
                                  preview-only ""
                                  (item-text s))
    (is s!category 'Link) ""))

; --------------------------------- Edit Item -------------------------------- ;

(def edit-url (i) (+ "edit?id=" i!id))

(def authentication-failure-msg (req)
  (pr "<b>AUTHENTICATION FAILURE!</b> Your work has not been saved.
       (You probably logged out in a different window while you were editing.)
       <p>Please copy & paste your work somewhere else, then
          <a href='/'>return to the homepage</a> and try again."
      (if (is (arg req "title") nil) "" (+ "<p>Title: " (esc-tags (arg req "title"))))
      "<p>Text:"
      "<pre>" (esc-tags (arg req "text")) "</pre>"))

(defop edit req
  (with (user (get-user req) i (only.safe-item (arg req "id")))
    (if (and i 
             (cansee user i)
             (editable-type i)
             (or (news-type i) (admin user) (author user i)))
        (if (arg req "auth")
             (handle-vars-form req
               ((fieldfn* i!type) user i)
               (fn (name val)
                   (unless (and (is name 'title) (len> val title-limit*))
                     (= (i name) val)))
               (fn () (save-item i)
                      (wipe (comment-cache* i!id))
                      (edit-page user i))
               (fn () (authentication-failure-msg req)))
             (edit-page user i))
        (if (arg req "auth")
          (authentication-failure-msg req)
          (pr "No such item.")))))

(def editable-type (i) (fieldfn* i!type))

(= fieldfn* (table))

(= (fieldfn* 'story)
   (fn (user s)
     (with (a (admin user)  e (editor user)  x (canedit user s) m (full-member user)
            cat '(choice sym Main Discussion Link))
       `((string2 title     ,s!title        t ,x)
         (string2 url       ,s!url          ,(or m (is s!category 'Link)) ,x)
         (pandoc  text      ,s!text         ,m ,(and x m))
         (,cat    category  ,s!category     ,m ,(and x m))
         ,@(standard-item-fields s a e x m)))))

(= (fieldfn* 'comment)
   (fn (user c)
     (with (a (admin user)  e (editor user)  x (canedit user c) m (full-member user))
       `((pandoc  text      ,c!text         t ,x)
         ,@(standard-item-fields c a e x m)))))

(def standard-item-fields (i a e x m)
  (let fields `((int     likes     ,(len (itemlikes* i!id)) ,a  nil)
                (yesno   deleted   ,i!deleted               ,a ,a)
                (sexpr   keys      ,i!keys                  ,a ,a)
                (string  ip        ,i!ip                    ,e  nil))
    (if i!draft (+ fields `((yesno draft ,i!draft ,x ,x)))
        fields)))

; Should check valid-url etc here too.  In fact make a fn that
; does everything that has to happen after submitting a story,
; and call it both there and here.

(def edit-page (user i (o msg))
  (let here (edit-url i)
    (shortpage user nil nil "Edit" here
      (pagemessage msg)
      (url-vars-form user ((fieldfn* i!type) user i) "/edit" `((id ,i!id))
                     "update" t)
      (br2)
      (tab (tr (tag (td width '100% style 'padding-right:80px)
                 (tab (display-item nil i user here)))))
      (hook 'edit user i))))

; ---------------------------- Comment Submission ---------------------------- ;

(def comment-login-warning (parent whence (o text))
  (login-page 'login+fb "You have to be logged in to comment."
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

(def process-comment (user parent text ip whence draft)
  (if (no user)
       (flink [comment-login-warning parent whence text])
      (empty text)
       (flink [addcomment-page parent (get-user _) whence text retry*])
       (atlet c (create-comment parent text user ip draft)
         (submit-item user c)
         whence)))

(defop submitcomment req
  (if (~check-auth req)
       (authentication-failure-msg req)
      (empty (arg req "text"))
       (addcomment-page (safe-item:arg req "parent") (get-user req)
                        (arg req "whence") (arg req "text") retry*)
       (atlet c (create-comment (safe-item:arg req "parent")
                                (arg req "text") (get-user req) req!ip
                                (arg req "draft"))
         (submit-item (get-user req) c)
         (if (arg req "draft")
             (edit-page (get-user req) c)
             (pr "<meta http-equiv='refresh' content='0; url="
                 (esc-tags (arg req "whence")) "' />")))))

(def comment-form (parent user whence (o text))
  (when (and user (cancomment user parent))
    (authform "/submitcomment" user
      (hidden 'parent parent!id)
      (hidden 'whence whence)
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
        (pr "save comment draft & preview"))
      (protected-submit (if (acomment parent) "reply" "add comment") t))))

(= comment-threshold* -20)

(def create-comment (parent text user ip draft)
  (newslog ip user 'comment (parent 'id))
  (let c (inst 'item 'type 'comment 'id (new-item-id)
                     'text text 'parent parent!id 'by user 'ip ip 'draft draft)
    (save-item c)
    (= (items* c!id) c)
    (push c!id (itemkids* parent!id))
    (push c comments*)
    c))

; ------------------------------ Comment Display ----------------------------- ;

(def display-comment-tree (c user whence (o indent 0) (o initialpar))
  (when (cansee user c)
  ; (when (cansee-descendant user c) ; we don't actually like the cansee-descendant behavior at all
    (let identifier c!id ; use (rand-id) if a comment can appear more than once on a page
      (when (should-collapse c user)
        (pr (gen-collapse-script c identifier))
        (tr (td (hspace (+ 27 (* indent 40)))
          (tag (a href "" class (+ "toggle-" identifier) style "font-size:11pt; color:#828282")
            (pr (+ "[+] Expand comment by " (get-user-display-name c!by)))))))
      (tr (tag (td class (+ "comment-" identifier)
                   style (if (should-collapse c user) "display:none" ""))
                 (tab
                   (display-1comment c user whence indent initialpar t)
                   (display-subcomments c user whence (+ indent 1))))))))

(def display-1comment (c user whence indent showpar (o hide-drafts))
  (if (or (no hide-drafts) (no c!draft))
    (row (tab (display-comment nil c user whence t indent showpar showpar)))))

(def display-subcomments (c user whence (o indent 0))
  ; changed frontpage-rank to realscore, but am unsure if this was correct:
  (each k (sort (compare > realscore) (kids c))
  ; (each k (sort (compare > frontpage-rank) (kids c))
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

; Comment caching turned off for now
; WARNING: Do not turn back on without fixing "like link" bug!

(= comment-caching* nil)

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

(def should-collapse (c user) (and (no (author user c)) (no (cansee nil c))))

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
                                           (pr (item-text c)))))
    (when (and astree (cansee_d user c) (live c))
      (para)
      (tag (font size 1)
        (if (and (~mem 'neutered c!keys)
                 (replyable c indent)
                 (comments-active c))
          (if (canreply user c) (underline (replylink c whence)))
            (fontcolor sand (pr "-----")))))))

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
         whence (or (only.urldecode whence) "/"))
    (if (and (only.comments-active i) (no i!draft) (canreply user i))
        (if user
            (addcomment-page i user whence)
            (login-page 'login+fb "You have to be logged in to comment."
                        (fn (u ip)
                          (ensure-news-user u)
                          (newslog ip u 'comment-login)
                          (addcomment-page i u whence))))
        (pr "No such item."))))

; ---------------------------------- Threads --------------------------------- ;

(def threads-url (user) (+ "threads?id=" user))

(newsop threads (id) 
  (if id
      (threads-page user id)
      (pr "No user specified.")))

(def threads-page (user subject)
  (if (profile subject)
      (withs (title (+ (get-user-display-name subject) "'s comments")
              label (if (is user subject) "my comments" title)
              here  (threads-url subject))
        (longpage-sb user (msec) nil label title here t
          (awhen (keep [and (cansee_d user _) (~subcomment _)]
                       (comments subject maxend*))
            (display-threads user it label title here))))
      (prn "No such user.")))

(def display-threads (user comments label title whence
                      (o start 0) (o end threads-perpage*))
  (tag (table width '100%)
    (each c (cut comments start end)
      (display-comment-tree c user whence 0 t))
    (spacerow 10)
    (row (tag (table width '100%)
      (tr (tag (td align 'right)
      (w/bars
        (when (< 0 start)
          (let newstart (max 0 (- start threads-perpage*))
            (navlink "Newer" display-threads
                    comments label title newstart start)))
        (when end
          (let newend (+ end threads-perpage*)
            (when (and (<= newend maxend*) (< end (len comments)))
              (navlink "Older" display-threads
                      comments label title end newend)))))))))))

(def submissions (user (o limit)) 
  (map item (firstn limit (uvar user submitted))))

(def comments (user (o limit))
  (map item (retrieve limit acomment:item (uvar user submitted))))
  
(def subcomment (c)
  (some [and (acomment _) (is _!by c!by) (no _!deleted)]
        (ancestors c)))

(def ancestors (i)
  (accum a (trav i!parent a:item self:!parent:item)))

; --------------------------------- Submitted -------------------------------- ;

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
        (longpage-sb user (msec) nil label label here t
          (aif (keep [and (astory _) (cansee_d user _)]
                     (submissions subject))
               (display-items user it label label here 0 perpage* t t))))
      (pr "No such user.")))

; ------------------------------------ RSS ----------------------------------- ;

(newsop rss ()
  (rss-feed (sort (compare > [if (no _!publish-time) _!time _!publish-time])
              (+ (retrieve perpage* [and live (no _!draft) (no (invisible _))] stories*)
                 (retrieve perpage* [and live (no _!draft) (no (invisible _))] comments*)))))

(def rss-feed (items)
  (tag (rss version "2.0")
    (tag channel
      (tag title (pr this-site*))
      (tag link (pr site-url*))
      (tag description (pr site-desc*))
      (each i items
        (tag item
          (tag title (if (astory i) (pr (eschtml i!title))
                         (let s (superparent i)
                           (pr (+ "Comment on " (eschtml s!title))))))
          (tag link (pr (+ site-url* (item-url i!id))))
          (tag author (pr (get-user-display-name i!by)))
          (tag description (pr (display-item-text i nil t))))))))

; -------------------------------- User Stats -------------------------------- ;

(newsop members () (memberspage user))

(newscache memberspage user 1000
  (longpage-sb user (msec) nil "full members" "members" "members" t
    (sptab
      (let i 0
        (each u (keep [full-member _]
                  (sort (compare > [karma _])
                    (keep [pos [cansee nil _] (submissions _)] (users))))
          (tr (tdr:pr (++ i) ".")
              (td (userlink user u))
              (tdr:pr (* karma-multiplier* (karma u))))
          (if (is i 10) (spacerow 30)))))))

(newsop contributors () (contributorspage user))

(newscache contributorspage user 1000
  (longpage-sb user (msec) nil "contributors" "contributors" "contributors" t
    (sptab
      (let i 0
        (each u (keep [no (full-member _)]
                  (sort (compare > [karma _])
                    (keep [pos [cansee user _] (submissions _)] (users))))
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

; ----------------------------- Comment Analysis ----------------------------- ;

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
  (listpage user (msec) (visible user (firstn maxend* comments*) t)
            "comments" "New Comments" "newcomments" nil t t t))

; ------------------------------------ Doc ----------------------------------- ;

(defop formatdoc req
  (msgpage (get-user req) formatdoc* "Formatting Options"))

(= formatdoc-url* "formatdoc")

(= formatdoc* 
"<p>Blank lines separate paragraphs.</p>

<div class=\"example-raw\">
<pre>Contents of first paragraph.
Contents of first paragraph continued.

Contents of second paragraph.</pre>
</div>

<div class=\"example-rendered\">
<p>Contents of first paragraph. Contents of first paragraph continued.</p>
<p>Contents of second paragraph.
</div>

<p>A paragraph beginning with a hash mark (#) is a subheading.</p>

<div class=\"example-raw\">
<pre># Subheading

Paragraph contents</pre>
</div>

<div class=\"example-rendered\">
<h1>Subheading</h1>
<p>Paragraph contents</p>
</div>

<p>A paragraph consisting of a single line with three or more
asterisks (***) will be rendered as a separator.</p>

<div class=\"example-raw\">
<pre>Contents above the separator

***

Contents below the separator</pre>
</div>

<div class=\"example-rendered\">
<p>Contents above the separator</p>
<hr />
<p>Contents below the separator</p>
</div>

<p>The preview for a post consists of everything that appears
before the first subheading or separator.  If there are no
subheadings or separators, then the preview is the first paragraph
(for long posts) or the entire post (for short posts).</p>

<div class=\"example-raw\">
<pre>This will appear before the fold.

***

This will appear after the fold.</pre>
</div>

<p>Text surrounded by dollar signs is rendered as LaTeX.</p>

<div class=\"example-raw\">
<pre>
This is my equation: $x^2 + x + 1 = 0$</pre>
</div>

<div class=\"example-rendered\">
This is my equation: <span class=\"math\">\\(x^2 + x + 1 = 0\\)</span>
</div>

<p>Text after a blank line that is indented by four or more spaces is
 reproduced verbatim.  (This is intended for code.)</p>

<div class=\"example-raw\">
<pre>This is my code:

    sum = 0
    for i in range(1000):
      if i % 3 == 0 or i % 5 == 0:
        sum += i
    print sum

It should output 233168.</pre>
</div>

<div class=\"example-rendered\">
<p>This is my code:</p>
<pre><code>sum = 0
for i in range(1000):
  if i % 3 == 0 or i % 5 == 0:
    sum += i
print sum</code></pre>
<p>It should output 233168.</p>
</div>

<p>See the <span class=\"doclink\">
<a href=\"http://johnmacfarlane.net/pandoc/demo/example9/pandocs-markdown.html\">
Pandoc markdown documentation</a></span> for additional formatting options.</p>")

; --------------------------------- Reset PW --------------------------------- ;

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
          (newestpage user))))

; ----------------------------------- Stats ---------------------------------- ;

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

; ---------------------------------- <edge> ---------------------------------- ;

;! need to make the how-to-contribute message less crazy
; <tr><td>
;   <table width='100%' style='width: 100%; background-color: #eaeaea;'><tbody>
;     <tr style='height:5px'></tr>
;     <tr><td><img src='s.gif' height='1' width='14'></td></tr>
;     <tr>
;       <td colspan='1'></td>
;       <td class='story' width='100%' style='text-align:left; font-size: 12pt; color: 254e7d;'>
;         <p>
;           This is a publicly visible discussion forum for foundational mathematical research in \"robust and beneficial\" artificial intelligence, as discussed in the Future of Life Institute's <a href='http://futureoflife.org/misc/open_letter' class='continue' style='text-decoration: underline;'>research priorities letter</a> and the Machine Intelligence Research Institute's <a href='https://intelligence.org/technical-agenda/' class='continue' style='text-decoration: underline;'>technical agenda</a>.
;         </p><p>
;           If you'd like to participate in the conversations here, see our <a href='/how-to-contribute' class='continue' style='text-decoration: underline;'>How to Contribute page »</a>
;         </p>
;       </td>
;     </tr>
;     <tr style='height:12px'></tr>
;   </tbody></table>
; </td></tr>
; <tr style='height:10px'></tr>
