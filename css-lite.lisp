(in-package "CSS-LITE")

;;; main interface

(defvar *css-stream* nil)

(defmacro css (&body rules)
  `(format *css-stream* "~@{~A~}" ,@(mapcan #'process-css-rule rules)))

(defmacro css-string (&body rules)
  `(with-output-to-string (*css-stream*)
    (css ,@rules)))

(defun inline-css (&rest properties)
  (format nil "~{~A~}" (process-css-properties properties t :newlines nil)))


(defmacro make-css-var (var-name var-val)
  `(progn 
     (setq ,var-name ,var-val)
     (setf (get ',var-name 'css-var) t)))

(defmacro make-css-func (func-name &body forms)
  `(progn
     (defun ,func-name ,@forms)
     (setf (get ',func-name 'css-func) t)))

(make-css-func comment (comment-string) (list (concatenate 'string "/*" comment-string) "*/"))

;; note this is a bit of a hack
;;
;; comments end up looking like this /* comment text :*/; notice the
;; colon before the closing */


;;; implementation

(defun selector-to-string (selector)
  (handler-case 
      (if (listp selector)
          (destructuring-bind (specifier element)
              selector
            (ecase specifier
              (:hover (format nil "~a:hover" (selector-to-string element)))
              (:id (css-id-name element))))
          (cond ((and (symbolp selector) (not (symbol-package selector))) (css-id-name selector))
                ((eql :and selector) ",")
                (t (to-string selector))))
    (error () (error "~s isn't a valid CSS selector." selector))))

(defun css-selectors-to-string (selectors)
  (reduce (lambda (s1 s2) (concatenate 'string s1 " " s2)) (mapcar #'selector-to-string selectors)))

(defvar +newline+ (format nil "~%"))


(defun css-func-p (val)
  (if (symbolp val)
      (get val 'css-func)
      nil))


(defun css-var-p (val)
  (if (symbolp val)
      (get val 'css-var)
      nil))

(defun expand-tree (tree)
  (let ((result '()))
    (labels ((scan (item)
               (if (listp item)
                   (if (css-func-p (car item))
                       ;; this calls the function
                       (scan (eval `(,(car item) ,@(cdr item)))) 
                   (map nil #'scan item))
                   (if (css-var-p item)
                       (scan (symbol-value item))
                    (push item result)))))
      (scan tree))
    (nreverse result)))


(defun process-css-properties (properties eval-vals &key (newlines t))
  (loop for (name val) on
       (expand-tree properties)
     by #'cddr appending
       (list 
        (if newlines +newline+ "") 
        (to-string name) ":" 
        (if eval-vals (to-string val) 
            `(to-string ,val)) ";")))

(defun process-css-rule (rule &key (parent-selectors nil))
  (let ((selectors (if parent-selectors
                       (flatten (list parent-selectors (car rule)))
                       (car rule)))
        (properties (cadr rule))
        (children-rules (cddr rule)))
    (append (list +newline+ (css-selectors-to-string selectors) " {")
            (process-css-properties properties nil)
            (list +newline+ "}" +newline+)
            (mapcan 
             #'(lambda (child-rules) 
                 (process-css-rule child-rules :parent-selectors selectors))
             children-rules))))

#-parenscript (defun css-id-name (symbol)
                (format nil "#~(~a~)" symbol))

(defun to-string (x)
  (cond ((stringp x) x)
	((symbolp x) (string-downcase (symbol-name x)))
        ((listp x) (apply #'concatenate 'string
                          (loop for (val . rest) on x
                                with comma = ", "
                                unless rest do (setf comma "")
                                collect (if (stringp val)
                                            (format nil "'~a'" val)
                                            (to-string val))
                                collect comma)))
	(t (princ-to-string x))))
