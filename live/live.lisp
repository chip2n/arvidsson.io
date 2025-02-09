(in-package #:site/live)

(defvar *on-reload-hooks* nil)

(defun start (serve-dir style-path)
  (site/live/server:start serve-dir)
  (site/live/socket:start)
  (file-watch:start)
  (file-watch:add-entry
   style-path
   (lambda (entry)
     (declare (ignore entry))
     (loop :for hook :in *on-reload-hooks* :do (funcall hook)))))

(defun stop ()
  (file-watch:stop)
  (site/live/socket:stop)
  (site/live/server:stop))

(defun reload-browser ()
  (site/live/socket:reload-browser))

(defun add-hook (hook)
  (push hook *on-reload-hooks*))
