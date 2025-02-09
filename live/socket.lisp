(in-package #:site/live/socket)

(defvar *connections* nil)
(defvar *server-handler* nil)

(defparameter *websocket-port* 4042)

(defun handle-open-connection (con)
  (format t "Connection: ~a~%" con)
  (push con *connections*))

(defun handle-message (connection message)
  (format t "~&New message: ~a: ~a~%" connection message))

(defun handle-close-connection (con)
  (format t "~&Connection closed: ~a~%" con)
  (setf *connections* (delete con *connections*))
  (websocket-driver:close-connection con))

(defun reload-browser ()
  (if *connections*
      (progn
        (loop :for con :in *connections* :do
          (format t "~&Reloading browser...~%")
          (websocket-driver:send con "reload")
          (websocket-driver:close-connection con))

        (setf *connections* nil))
      (warn "~&No connections - cannot reload browsers")))

(defun clack-server (env)
  (let ((ws (websocket-driver:make-server env)))
    (websocket-driver:on :open ws
                         (lambda () (handle-open-connection ws)))

    (websocket-driver:on :message ws
                         (lambda (msg) (handle-message ws msg)))

    (websocket-driver:on :close ws
                         (lambda (&key code reason)
                           (declare (ignore code reason))
                           (handle-close-connection ws)))
    (lambda (responder)
      (declare (ignore responder))
      (websocket-driver:start-connection ws))))

(defun start ()
  (when *server-handler* (stop))
  (setf *server-handler* (clack:clackup #'clack-server :port *websocket-port*)))

(defun stop ()
  (loop :for con :in *connections* :do
    (websocket-driver:close-connection con))
  (setf *connections* nil)
  (clack:stop *server-handler*)
  (setf *server-handler* nil))
