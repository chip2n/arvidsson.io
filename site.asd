(asdf:defsystem #:site
  :description "My personal website"
  :author "Andreas Arvidsson <andreas@arvidsson.io>"
  :license "MIT"
  :version "0.0.1"
  :serial t
  :depends-on (#:alexandria)
  :components ((:file "package")
               (:file "page")))

(asdf:defsystem #:site/live
  :description "Server for hot reloading web page"
  :author "Andreas Arvidsson <andreas@arvidsson.io>"
  :license "MIT"
  :version "0.0.1"
  :serial t
  :depends-on (#:clack #:websocket-driver #:trivial-file-watch)
  :components ((:file "live/package")
               (:file "live/socket")
               (:file "live/server")
               (:file "live/live")))
