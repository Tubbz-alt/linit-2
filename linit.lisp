(in-package #:linit)

(defvar *services* nil)

(defmacro defservice (name &rest initargs)
  (let ((new-service (gensym)))
    `(let ((,new-service (make-instance 'service
                                       :name ',name
                                       ,@initargs)))
       (if (find-service ',name)
           (replace-service ,new-service)
           (add-service ,new-service)))))

(defun find-service (name)
  (find-if (lambda (service)
             (eq (name service) name))
           *services*))

(defun replace-service (new-service)
  (setf *services* (remove-if (lambda (service)
                                (eq (name service) (name new-service)))
                              *services*))
  (add-service new-service))

(defun add-service (service)
  (push service *services*))

(deftype service-state ()
  '(member started stopped errored))

(defclass service ()
  ((pid :accessor pid :type integer)
   (state :accessor state :type service-state)
   (name :reader name :initarg :name :type symbol)
   (start :initarg :start :reader start :type function)
   (depends-on :initarg :depends-on :type list)))

(defun load-services (path)
  (dolist (service (directory path))
    ;; For some reason, this needs to be re-applied for the load'ed
    ;; file to be in the correct package.
    (in-package #:linit)
    (load service)))

(defun start-service (service)
  (let ((pid (sb-posix:fork)))
    (cond
      ((<= pid -1) (setf (state service) 'errored))
      ((= pid 0) (funcall (start service)))
      (t (progn
           (setf (pid service) pid)
           (setf (state service) 'started)
           (sb-thread:make-thread
            (lambda ()
              (let ((status (make-array 1 :element-type '(signed-byte 32))))
                (sb-posix:waitpid pid 0 status)
                (let ((st (aref status 0)))
                  (when (sb-posix:wifexited st)
                    (setf (state service) (if (= (sb-posix:wexitstatus st) 0)
                                              'stopped 'errored))))))
            :name (symbol-name (name service))))))))

(defun main (args)
  (declare (ignore args))
  (load-services #p"/lib/linit/*.lisp")
  (dolist (service *services*)
    (start-service service))
  (sb-impl::toplevel-repl nil))
