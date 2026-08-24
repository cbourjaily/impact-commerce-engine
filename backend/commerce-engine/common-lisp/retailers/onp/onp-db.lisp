;;; onp-db.lisp

#|
ONP's wrapper: loads the generic Impact-format parser (which
itself loads product.lisp, which loads db-builder.lisp), then
supplies the two things that are ONP-specific to the Impact
Radiius catilogs: the quantity-extraction heuristics and this
retailer's file paths/names.
|#

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *onp-dir*
    (make-pathname :directory (pathname-directory
				(or *compile-file-truename* *load-truename*))))
  (defparameter *common-lisp-dir*
    (merge-pathnames "../../" *onp-dir*))
  (load (merge-pathnames "throughput/impact-parser.lisp" *common-lisp-dir*)))


;;; onp's Impact-format CSV catalog -- read directly from the raw
;;; tab-delimited feed. 
(defparameter *onp-impact-catalog*
  (merge-pathnames "../../../data/onp/impact-format/Updated-ONP-Catalog_IR.txt" *onp-dir*))


;;; onp's loaded catalog rows
(defparameter *onp-impact-rows*
  (load-delimited *onp-impact-catalog* #\Tab))


;;; extract-raw-quantity : product-name -> string or nil
;;; Consumes a name field and returns a normalized string describing
;;; the product's size/quantity, if the name expressesone at all.
;;; Tries, in order, from most to least specific:
;;;   1. A trailing parenthetical, e.g. "... (16 oz)" -> "16 oz"
;;;   2. A weight-and-case-count combo that's split across two
;;;      separated parts of the name, e.g.
;;;      "2.8 oz, Chicken & Sweet Potato (Case of 24) Flavor"
;;;      -> "2.8 oz Case of 24"
;;;   3. Single regex patterns for the common standalone shapes:
;;;      weight (oz/lb/Cup), count (ct/Count/pack/Piece Set/month
;;;      supply/Case of N), and Size (Inch, N-N Inch).
;;; Falling through to nil is a legitimate result -- some names
;;; genuinely don't express a quantity ("100% Recycled", etc.) --
;;; not a sign the extraction failed.

(defun extract-parenthetical-quantity (name)
  (let ((end (1- (length name))))
    (cond
      ((not (eq (aref name end) #\))) nil)
      (T
       (labels ((find-start (&optional (current end))
		  (cond
		    ((= current 0) nil)
		    ((eq (aref name (1- current)) #\() current)
		    (T (find-start (1- current))))))
	 (let ((start (find-start)))
	   (if start
	       (subseq name start end)
	       nil)))))))
 
(defun match (pattern string)
  (multiple-value-bind (start end)
      (cl-ppcre:scan pattern string)
    (when start
      (subseq string start end))))
 
(defun extract-oz-case-quantity (name)
  (let ((oz-pos (search " oz" name))
	(case-pos (search "Case of" name)))
    (when (and oz-pos case-pos)
      (let* ((oz-start
	       (or (position-if #'digit-char-p name :end oz-pos)
		   oz-pos))
	     (case-num-start
	       (+ case-pos (length "Case of")))
	     (case-num-start
	       (or (position-if #'digit-char-p
				name
				:start case-num-start)
		   case-num-start))
	     (case-end
	       (or (position-if-not #'digit-char-p
				    name
				    :start case-num-start)
		   (length name))))
	(format nil "~a ~a"
		(subseq name oz-start (+ oz-pos 3))
		(string-trim '(#\Space #\()
			     (subseq name case-pos case-end)))))))
 
(defun extract-quantity-candidate (name)
  (or
   (match "\\b[0-9]+(?:\\.[0-9]+)?\\s*(?:oz|lb|Cup)\\b" name)
   (match "\\b[0-9]+\\s+Unscented\\s+Bags\\b" name)
   (match "\\b[0-9]+(?:\\.[0-9]+)?\\s+Inch\\b" name)
   (match "\\b[0-9]+\\s*(?:ct|Count)\\b" name)
   (match "\\b[0-9]+\\s+[Pp]ack\\b" name)
   (match "\\b[0-9]+\\s+Piece\\s+Set\\b" name)
   (match "\\b[0-9]+\\s+[Mm]onth\\s+[Ss]upply\\b" name)
   (match "\\b[Cc]ase\\s+of\\s+[0-9]+\\b" name)
   (match "\\b[0-9]+-[0-9]+\\s+[Ii]nch\\b" name)))
 
(defun extract-raw-quantity (name)
  (or (extract-parenthetical-quantity name)
      (extract-oz-case-quantity name)
      (extract-quantity-candidate name)))
 
 
;;; onp's list of product structs -- built via the generic
;;; rows->products, with ONP's retailer name and quantity heuristic
;;; passed in as the two retailer-specific pieces.
 
(defvar *products*
  (rows->products (cdr *onp-impact-rows*)
		   :retailer "Only Natural Pet"
		   :raw-quantity-fn #'extract-raw-quantity))


;;; onp's database path -- overrides the nil placeholder declared in
;;; product.lisp.

(defparameter *db-path*
  (merge-pathnames "../../../database/impact.db" *onp-dir*))


;;; load-onp : nil -> list-of failures
;;; Wraps *products*/*db-path* (already bound above) in the same
;;; calling convention as the generic retailers' load-* functions --
;;; so ONP can be included alongside them in a manual full-refresh
;;; without needing a special case for it.

(defun load-onp ()
  (load-products-to-db *products* *db-path*))

