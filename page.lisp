(in-package #:site)

;; * Internals

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
  (ensure-directories-exist #P"/tmp/public/")
  (ensure-directories-exist #P"/tmp/public/static/")
  (alexandria:with-output-to-file (out "/tmp/public/index.html" :if-exists :supersede)
    (render-tree out (expand-tags (funcall (get-page :index)))))
  (alexandria:with-output-to-file (out "/tmp/public/projects.html" :if-exists :supersede)
    (render-tree out (expand-tags (funcall (get-page :projects)))))
  (alexandria:with-output-to-file (out "/tmp/public/project-zball.html" :if-exists :supersede)
    (render-tree out (expand-tags (funcall (get-page :project-zball)))))
  (alexandria:with-output-to-file (out "/tmp/public/project-site.html" :if-exists :supersede)
    (render-tree out (expand-tags (funcall (get-page :project-site)))))
  (uiop:copy-file (asset-path "style.css") #P"/tmp/public/static/style.css")
  (uiop:copy-file (asset-path "live.js") #P"/tmp/public/static/live.js")
  (uiop:copy-file (asset-path "game.js") #P"/tmp/public/static/game.js")
  (uiop:copy-file (asset-path "game.wasm") #P"/tmp/public/static/game.wasm")
  (uiop:copy-file (asset-path "zball.png") #P"/tmp/public/static/zball.png")

  ;; Reload browser if site/live package is loaded
  (when-let (pkg (find-package 'site/live))
    (funcall (intern "RELOAD-BROWSER" pkg))))

(defun start-dev ()
  (asdf:load-system 'site/live)
  (compile-pages)
  (setf *auto-compile-pages* t)
  (when-let (pkg (find-package 'site/live))
    (funcall (intern "START" pkg) "/tmp/public/" (asset-path))
    (funcall (intern "ADD-HOOK" pkg) (lambda ()
                                       (format t "Style changed - recompiling...")
                                       (compile-pages)))))

;; * Website

;; ** Root

(define-tag page ()
  `(:html
     (:head
       (:link :rel "stylesheet" :type "text/css" :href "static/style.css")
       (:link :rel "stylesheet" :type "text/css" :href "static/prism.css")
       ,(when (dev-mode-p)
          `(:script :type "text/javascript" :src "static/live.js"))
       (:meta :name "viewport" :content "width=device-width, initial-scale=1"))
     (:body
       (:div :id "root-container"
         (:site-header
          (:$link :label "[home]" :url "index.html")
          (:$link :label "[projects]" :url "projects.html")
          (:$link :label "[about]" :url "about.html"))
         (:div :id "root-content" ,@body)
         (:site-footer)))))

(define-tag site-header ()
  `(:div
     (:div :id "site-header"
       ;; TODO content description?
       (:a :id "logo" :href "index.html" ,(embed-asset "logo.svg"))
       (:div :id "site-header-menu"
         (:ul :class "h-menu"
           ,@(loop :for form :in body :collect `(:li ,form)))
         (:a :class "menu-item-icon" :href "https://github.com/chip2n"
           ,(embed-asset "icon-github.svg"))))))

(define-tag site-footer ()
  `(:div :id "site-footer"
     (:hr)
     (:p "λ")))

(define-tag page-header (title src)
  `(:div :class "page-header"
     (:h1 ,title)
     ,(when src
        `(:$link :label "[source]" :url ,src))
     ,@body))

;; ** Page: index.html

(define-page index ()
  `(:page
    (:div :class "document"
      (:page-header :title "Home")
      (:h2 "Section 1")
      (:p "body1")
      (:p "body2")
      (:p "body3")
      (:h2 "Section 1")
      (:p "body1")
      (:p "body2")
      (:p "body3"))))

;; ** Projects

(define-tag project-root (title src hero sidebar)
  `(:div :class "document"
     (:page-header :title ,title :src ,src)
     ,hero
     (:div :id "project-container"
       ,@body
       ,(when sidebar `(:project-sidebar ,sidebar)))))

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
     (:div :class "image"
       ,img)
     (:hr)
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
     :sidebar (:ul
                (:li (:span "Language: " (:$link :label "Zig" :url "https://ziglang.org/")))
                (:li "Platforms:"
                  (:ul
                    (:li "Windows")
                    (:li "Mac")
                    (:li "Linux")
                    (:li "Web")))
                (:li "Dependencies:"
                  (:ul
                    (:li (:$link :label "sokol" :url "https://github.com/floooh/sokol"))
                    (:li (:$link :label "stb_image" :url "https://github.com/nothings/stb")))))
     (:div
       (:p "A clone of the classic Breakout/Arkanoid game, with way too many particle effects added. I wrote this game mainly as an exercise in actually finishing a project for once. I picked Breakout since I figured it would be one of the simpler games to make, while still providing the opportunity to extend it with more fancy stuff through power ups.")
       (:h2 "Implementation")
       (:p "The game is implemented using the Zig programming language. Rendering is handled with the excellent sokol library (through the sokol-zig bindings), allowing it to be exported to multiple platforms including the web (through WASM).")
       (:h2 "Controls")
       (:ul
         (:li "Mouse / Arrow keys: Move the paddle")
         (:li "Space: Activate power-up")
         (:li "Backspace: Open menu / Go back"))))))

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
       (:p "Hot reloading of the static assets are simply done by watching the assets directory from the lisp runtime and recompile all the pages. I initially had a more fancy tracking of dependencies, but the html generation is fast enough so far that it wasn't worth it (the runtime startup is avoided since the file watchers are hosted inside the lisp process).")))))

;; ** Utils

(define-tag $link (label url)
  `(:a :href ,url ,label))
