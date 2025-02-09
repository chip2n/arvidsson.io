(in-package #:site/live/server)

(defvar *handler* nil)
(defparameter *port* 4043)

(defun app (env)
  (declare (ignore env))
  '(404 (:content-type "text/plain") ("Not Found")))

(defun start (serve-dir)
  (when *handler* (stop))
  (setf *handler*
        (clack:clackup
         (lack:builder
          (:static :path "/" :root serve-dir)
          'app)
         :server :hunchentoot
         :port *port*))
  (format t "Serving files at ~A~%" serve-dir))

(defun stop ()
  (when *handler*
    (clack:stop *handler*)
    (setf *handler* nil)))

(defun running-p ()
  (not (null *handler*)))
