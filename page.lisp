(in-package #:site)

;; * Internals

(defparameter *output-path* "./public/")
(defvar *pages* (make-hash-table))
(defvar *tags* (make-hash-table))
(defvar *auto-compile-pages* nil)

(defmacro define-page (name options &body body)
  `(progn
     (setf (gethash (alexandria:make-keyword ',name) *pages*)
           (lambda () (progn ,@body)))
     (when *auto-compile-pages* (compile-pages))))

(defmacro define-tag (name args &body body)
  `(progn
     (setf (gethash (alexandria:make-keyword ',name) *tags*)
           (lambda ,(cons '&key (append args '(body)))
             (declare (ignorable body))
             ,@body))
     (when *auto-compile-pages* (compile-pages))))

(defun get-page (name)
  (gethash name *pages*))

(defun remove-page (name)
  (remhash name *pages*))

(defun get-tag (name)
  (gethash name *tags*))

(defun remove-tag (name)
  (remhash name *tags*))

(defun asset-path (&optional (file ""))
  (asdf:system-relative-pathname 'site (merge-pathnames "assets/" file)))

(defun output-path (&optional (file ""))
  (uiop:merge-pathnames* file *output-path*))

(defun static-path (&optional (file ""))
  (reduce #'uiop:merge-pathnames* (list "static/" file *output-path*)))

(defun embed-asset (file)
  (uiop:read-file-string (asset-path file)))

(defun tagp (name)
  (nth-value 1 (get-tag name)))

(defun expand-tags (tree)
  (cond
    ((and (consp tree) (tagp (car tree)))
     (let ((ntree (normalize-tree tree)))
       (expand-tags
        (apply #'funcall (get-tag (car ntree))
               (append (cadr ntree) `(:body ,(caddr ntree)))))))
    ((consp tree)
     (let ((ntree (normalize-tree tree)))
       `(,(car ntree) ,@(cadr ntree) ,@(mapcar #'expand-tags (caddr ntree)))))
    (t tree)))

(defun normalize-tree (tree)
  (let ((args (cdr tree))
        (keys nil))
    (loop :while (keywordp (car args))
          :do (push (pop args) keys)
              (push (pop args) keys))
    (setf keys (nreverse keys))
    (list (car tree) keys args)))

;; ** Renderer

(defun html-attr (x)
  (cond
    ((typep x 'boolean) (if x "true" "false"))
    (t x)))

(defun render-tree (out tree)
  (cond
    ((consp tree)
     (let* ((ntree (normalize-tree tree))
            (el (car ntree))
            (attrs (cadr ntree))
            (body (caddr ntree)))

       (write-string "<" out)
       (write-string (symbol-name el) out)
       (loop :for (k v) :on attrs :by #'cddr
             :do (write-string " " out)
                 (write-string (symbol-name k) out)
                 (write-string "='" out)
                 (write-string (html-attr v) out)
                 (write-string "'" out))
       (write-string ">" out)

       (loop :for form :in body
             :do (render-tree out form))

       (write-string "</" out)
       (write-string (symbol-name el) out)
       (write-string ">" out)))
    ((null tree) nil)
    (t (write-string tree out)))

  ;; (loop :for (k v) :on '(:a 1 :b 2) :by #'cddr :collect (cons k v))
  )

;; * Compilation

(defun dev-mode-p ()
  "Returns T if site/live package is loaded."
  (not (null (find-package 'site/live))))

(defun compile-pages ()
  (ensure-directories-exist (output-path))
  (ensure-directories-exist (static-path))

  ;; Compile all pages
  (loop :for page :being :the :hash-keys :of *pages*
        :for file := (format nil "~A.html" (string-downcase (symbol-name page)))
        :for path := (output-path file)
        :do (alexandria:with-output-to-file (out path :if-exists :supersede)
              (format t "Rendering ~A...~%" path)
              (render-tree out (expand-tags (funcall (get-page page))))))

  ;; Copy all static files
  (loop :for path :in (uiop:directory-files (asset-path))
        :do (format t "Copying static file ~A...~%" path)
            (uiop:copy-file path (static-path (file-namestring path))))

  ;; Reload browser if site/live package is loaded
  (when-let (pkg (find-package 'site/live))
    (funcall (intern "RELOAD-BROWSER" pkg))))

(defun start-dev ()
  (asdf:load-system 'site/live)
  (compile-pages)
  (setf *auto-compile-pages* t)
  (when-let (pkg (find-package 'site/live))
    (funcall (intern "START" pkg) (output-path) (asset-path))
    (funcall (intern "ADD-HOOK" pkg)
             (lambda ()
               (format t "Style changed - recompiling...")
               (compile-pages)))))

;; * Website

;; ** Root

(define-tag page ()
  `(:html
     (:head
       (:link :rel "stylesheet" :type "text/css" :href "static/style.css")
       (:link :rel "stylesheet" :type "text/css" :href "static/prism.css")
       (:link :rel "icon" :type "image/x-icon" :href "static/favicon.ico")
       ,(when (dev-mode-p)
          `(:script :type "text/javascript" :src "static/live.js"))
       (:meta :name "viewport" :content "width=device-width, initial-scale=1"))
     (:body
       (:div :id "root-container"
         (:site-header
          (:a :href "index.html" :aria-label "Home" "[home]")
          (:a :href "projects.html" :aria-label "Projects" "[projects]"))
         (:div :id "root-content" ,@body)
         (:site-footer)))))

(define-tag site-header ()
  `(:div
     (:div :id "site-header"
       ;; TODO content description?
       (:div :aria-hidden t ,(embed-asset "logo.svg"))
       (:div :id "site-header-menu"
         (:ul :class "h-menu"
           ,@(loop :for form :in body :collect `(:li ,form)))
         (:a
           :class "menu-item-icon"
           :href "https://github.com/chip2n"
           :aria-label "GitHub"
           (:div :aria-hidden t ,(embed-asset "icon-github.svg")))))))

(define-tag site-footer ()
  `(:div :id "site-footer"
     (:hr)
     (:p :aria-hidden t "λ")))

(define-tag page-header (title src)
  `(:div :class "page-header"
     (:h1 ,title)
     ,(when src
        `(:a :href ,src :aria-label "Source" "[source]"))
     ,@body))

;; ** Page: index.html

(define-page index ()
  `(:page
    (:div :class "document"
      (:page-header :title "Home")
      (:p "Welcome to my tiny corner on the information superhighway known as the World Wide Web! This is the home for my various projects - not many right now, but hopefully the list will grow with time.")

      (:h2 "About me")
      (:p "I've worked in the software industry professionally since ~2010, but my interests in computers and programming goes all the way back to the late 90s I first encountered tools such as QBasic, Visual Basic and Delphi. Early on, I also took an interest in game development, experimenting with Klik & Play, Game Factory and Blitz3D / DarkBasic.")
      (:p "After a brief stint as a backend engineer (Python + Tornado), I moved into world of mobile development (native development using Swift/Kotlin as well as cross-platform development using Flutter). My current position is CTO at Remente, in charge of both platforms as well as auxiliary things like UI/UX and general product development.")
      (:p "I love learning new programming languages and have dabbled in most popular ones, but I currently favor Zig (when I need performance and cross-platform executables) and Common Lisp (when I want to mess around with fancy macros). I'm also a big fan of Emacs (sorry vimmers - but you're cool too).")
      (:p "I also love music and play guitar, bass, tenor saxophone and harmonica 🎵"))))

;; ** Projects

(define-tag project-root (title src hero)
  `(:div :class "document"
     (:page-header :title ,title :src ,src)
     ,hero
     ,@body))

(define-tag project-sidebar ()
  `(:div :class "project-sidebar" ,@body))

;; *** Page: projects.html

(define-page projects ()
  `(:page
    (:page-header :title "Projects")
    (:div :class "project-showcase"
      (:project-card
       :title "zball"
       :img (:img :class "project-img pixelated" :src "static/zball.png")
       :tags ("#zig" "#game")
       :url "project-zball.html"
       "A clone of the classic Breakout/Arkanoid game.")
      (:project-card
       :title "arvidsson.io"
       :img (:div :class "project-img" ,(embed-asset "project-site.svg"))
       :tags ("#lisp" "#web")
       :url "project-site.html"
       "This website! Generated using some custom lisp code."))))

(define-tag project-card (title img tags url)
  `(:div :class "project-card clickable-parent focusable-parent"
     (:div :class "image" :aria-hidden t
       ,img)
     (:hr :aria-hidden t)
     (:div :class "details"
       (:a :href ,url (:h2 ,title))
       (:div :class "project-body"
         ,@body)
       (:div :class "tags"
         ,@(loop :for tag :in tags :collect `(:span ,tag))))))

;; *** Page: project-zball.html

(define-page project-zball ()
  `(:page
    (:project-root
     :title "ZBall"
     :src "https://github.com/chip2n/zball"
     :hero (:game-canvas)
     (:div :id "project-container"
       (:div
         (:p "A clone of the classic Breakout/Arkanoid game, with way too many particle effects added. I wrote this game mainly as an exercise in actually finishing a project for once. I picked Breakout since I figured it would be one of the simpler games to make, while still providing the opportunity to extend it with more fancy stuff through power ups.")
         (:h2 "Implementation")
         (:p
           (:span "The game is implemented using the Zig programming language. Rendering is handled with the excellent ")
           (:a :href "https://github.com/floooh/sokol" "sokol")
           (:span " library (through the sokol-zig bindings), allowing it to be exported to multiple platforms including the web (through WASM)."))
         (:h2 "Controls")
         (:ul
           (:li "Mouse / Arrow keys: Move the paddle")
           (:li "Space: Activate power-up")
           (:li "Backspace: Open menu / Go back")))
       (:project-sidebar
        (:ul :aria-label "Project information"
          (:li (:span (:b "Language: ") "Zig"))
          (:li (:b "Platforms:")
            (:ul
              (:li "Windows")
              (:li "Mac")
              (:li "Linux")
              (:li "Web")))
          (:li (:b "Dependencies:")
            (:ul
              (:li "sokol")
              (:li "stb_image")))))))))

(define-tag game-canvas ()
  `(:div
     (:div :id "game-container"
       (:canvas :class "game" :id "canvas" :oncontextmenu "event.preventDefault()"))
     (:script "
      var Module = {
        preRun: [],
        postRun: [],
        print: (function() {
            return function(text) {
                text = Array.prototype.slice.call(arguments).join(' ');
                console.log(text);
            };
        })(),
        printErr: function(text) {
            text = Array.prototype.slice.call(arguments).join(' ');
            console.error(text);
        },
        canvas: (function() {
            return document.getElementById('canvas');
        })(),
        setStatus: function(text) { },
        monitorRunDependencies: function(left) { },
      };
      window.onerror = function() {
        console.log(\"onerror: \" + event.message);
      };")
     (:script :async t :src "static/game.js")))

;; *** Page: project-site.html

(define-page project-site ()
  `(:page
    (:project-root
     :title "arvidsson.io"
     :src "https://github.com/chip2n/arvidsson.io"
     (:div :id "project-container"
       (:div
         (:p "This website is generated using some custom code written in Common Lisp (SBCL). The goal was to have a place to host my current and future projects, as well as polishing up my web dev chops.")
         (:h2 "Implementation")
         (:p "When I originally started building the site, I had a few requirements:")
         (:ul
           (:li "Write pages and custom tags using S-expressions")
           (:li "Expose the entire lisp language in page and tag definitions")
           (:li "Automatic hot reload of static assets"))
         (:p "I'm a big fan of the homoiconicity of lisp languages, and I knew that writing the pages in S-expressions would allow me to mix tags and code relatively effortlessly. There's some other benefits as well, such as not having to write closing tags and allowing me to use some neat structural editing tools in Emacs.")
         (:p "I tried finding a good balance between abstraction and ease of use, and after a few unsuccessful attempts I landed on simply using the quote/unquote mechanism of Common Lisp directly. Hopefully, the code will be relatively easy to understand when I get back after a few months to add more stuff.")
         (:p "Hot reloading of the static assets are simply done by watching the assets directory from the lisp runtime and recompile all the pages. I initially had a more fancy tracking of dependencies, but the html generation is fast enough so far that it wasn't worth it (the runtime startup is avoided since the file watchers are hosted inside the lisp process)."))
       (:project-sidebar
        (:ul :aria-label "Project information"
          (:li (:span (:b "Language: ") "Common Lisp"))
          (:li (:b "Platforms:")
            (:ul
              (:li "Linux")))
          (:li (:b "Dependencies:")
            (:ul
              (:li "alexandria")))
          (:li (:b "Dependencies (DEV):")
            (:ul
              (:li "clack")
              (:li "websocket-driver")
              (:li "trivial-file-watch")))))))))
