;;;; esrap.lisp

;;;; This is a part of esrap-liquid TDPL for Common Lisp
;;;; Alexander Popolitov, 2013
;;;; For licence, see COPYING

(in-package :esrap-liquid)

;;; MAIN INTERFACE

(defmacro with-tmp-rule ((var expression) &body body)
  (with-gensyms (g!-expr g!-rule)
    `(let ((,g!-expr ,expression))
       (unwind-protect (progn (setf (gethash ',g!-rule *rules*)
				    (funcall (compile nil `(lambda ()
							     ,(make-rule-lambda
							       'esrap-tmp-rule ()
							       (list (if (symbolp ,g!-expr)
									 `(v ,,g!-expr)
									 ,g!-expr)))))))
			      (let ((,var ',g!-rule))
				,@body))
	 (remhash ',g!-rule *rules*)))))


(defun parse-token-iter (expression token-iter &key junk-allowed)
  (let ((the-iter token-iter)
	(*cache* (make-cache))
	(the-position 0)
	(the-length 0))
    (tracing-init
      (with-tmp-rule (tmp-rule expression)
	(let ((result (handler-case (descend-with-rule tmp-rule)
			(simple-esrap-error (e)
			  (if junk-allowed
			      (values nil 0)
			      (error e))))))
	  (if-debug "after tmp-rule")
	  (when (not junk-allowed)
	    (handler-case (descend-with-rule 'eof)
	      (simple-esrap-error ()
		(fail-parse "Didnt make it to the end of the text"))))
	  (values result the-length))))))

(defun mk-esrap-iter-from-string (str start end)
  (mk-cache-iter (mk-string-iter (subseq str start end))))

(defun mk-esrap-iter-from-stream (stream)
  (mk-cache-iter (mk-stream-iter stream)))


(defun parse (expression text &key (start 0) end junk-allowed)
  "Parses TEXT using EXPRESSION from START to END. Incomplete parses
are allowed only if JUNK-ALLOWED is true."
  (parse-token-iter expression (mk-esrap-iter-from-string text start end) :junk-allowed junk-allowed))

(defun parse-stream (expression stream &key junk-allowed)
  "Parses STREAM using EXPRESSION. Incomplete parses are allowed if JUNK-ALLOWED is true."
  (parse-token-iter expression (mk-esrap-iter-from-stream stream) :junk-allowed junk-allowed))


(defmacro character-ranges (&rest char-specs)
  (with-gensyms (g!-char)
    (macrolet ((fail ()
		 `(error "Character range specification is either a character or list of 2 characters, but got ~a."
			 char-spec)))
      (iter (for char-spec in char-specs)
	    (collect (cond ((characterp char-spec) `((char= ,g!-char ,char-spec) ,g!-char))
			   ((consp char-spec)
			    (destructuring-bind (start-char end-char) char-spec
			      (if (and (characterp start-char)
				       (characterp end-char))
				  `((and (>= (char-code ,g!-char) ,(char-code start-char))
					 (<= (char-code ,g!-char) ,(char-code end-char)))
				    ,g!-char)
				  (fail))))
			   (t (fail)))
	      into res)
	    (finally (return `(let ((,g!-char (descend-with-rule 'character nil)))
				(cond ,@res
				      (t (fail-parse-format "Character ~s does not belong to specified range"
							    ,g!-char))))))))))

(defvar *indentation-hint-table* nil)

(defun hint-slime-indentation ()
  (let* ((swank (find-package :swank))
         (tables (when swank
                   (find-symbol (string '#:*application-hints-tables*) swank))))
    (when tables
      (let ((table (make-hash-table :test #'eq)))
        (setf (gethash 'defrule table)
              '(4 4 &rest (&whole 2 &lambda &body)))
        (set tables (cons table (remove *indentation-hint-table* (symbol-value tables))))
        (setf *indentation-hint-table* table))
      t)))

(hint-slime-indentation)
