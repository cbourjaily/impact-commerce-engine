;;; common-lisp/utilities/new-retailers.lisp
;;;
;;; Compares catalogs_info_file.xml against the retailers already
;;; configured (ONP's own advertiserId, plus everything in
;;; shell/update-onp.sh's GENERIC_RETAILERS array) and prints only
;;; the ones NOT yet added -- no more eyeballing a 1000+ line XML
;;; dump by hand.
;;;
;;; Reads the XML as plain text and regex-extracts each
;;; <catalog>...</catalog> block's fields directly (via cl-ppcre,
;;; already a real dependency this project uses elsewhere) rather
;;; than shelling out to xmllint or pulling in a full XML parser as
;;; a new dependency -- catalogs_info_file.xml's structure is simple
;;; and consistent enough that this is safe, and it keeps this
;;; self-contained with no new moving parts.
;;;
;;; *known-advertiser-ids* is a SECOND source of truth, kept in sync
;;; with update-onp.sh BY HAND -- deliberately, not auto-derived.
;;; Parsing bash array syntax from Lisp is more fragile than it's
;;; worth for a list this short; update this list yourself whenever
;;; you add a retailer to GENERIC_RETAILERS (or ONP's own id, if
;;; that somehow ever changed).
;;;
;;; Groups multiple <catalog> entries sharing the same advertiserId
;;; into ONE summary row with a TOTAL record count summed across all
;;; of them -- this is specifically what makes a Joom-scale outlier
;;; (~100 entries under one id) obvious from the numbers alone,
;;; rather than something you'd only notice by manually counting
;;; repeated blocks.
;;;
;;; Usage: load this file (SLIME C-c C-k, or `sbcl --script`) --
;;; report-new-retailers runs automatically at the bottom.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload :cl-ppcre :silent t))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (boundp '*utilities-dir*)
    (defparameter *utilities-dir*
      (make-pathname :directory (pathname-directory
				  (or *load-truename* *compile-file-truename*))))))

(defparameter *xml-path*
  (merge-pathnames "../../data/catalogs_info_file.xml" *utilities-dir*))

;;; Keep in sync BY HAND with shell/update-onp.sh -- see file header
;;; comment above for why this isn't auto-derived.
(defparameter *known-advertiser-ids*
  (list "6955634"   ; ONP (custom-parsed)
	"7479390"   ; SinoCrafted (generic)
	"7452908")) ; Terra (generic)

;;; extract-field : tag block -> string or nil

(defun extract-field (tag block)
  (multiple-value-bind (match groups)
      (cl-ppcre:scan-to-strings (format nil "<~a>(.*?)</~a>" tag tag) block)
    (declare (ignore match))
    (when groups (aref groups 0))))

;;; parse-catalogs : pathname -> list of plist
;;; Only format=IR entries -- (:advertiser-id STR :location STR
;;; :num-records INTEGER).

(defun parse-catalogs (path)
  (let ((xml (with-open-file (s path :direction :input)
	       (let ((buf (make-string (file-length s))))
		 (read-sequence buf s)
		 buf))))
    (loop for block in (cl-ppcre:all-matches-as-strings "(?s)<catalog>.*?</catalog>" xml)
	  when (string= (extract-field "format" block) "IR")
	    collect (list :advertiser-id (extract-field "advertiserId" block)
			  :location (extract-field "location" block)
			  :num-records (or (parse-integer (or (extract-field "numRecords" block) "0")
							   :junk-allowed t)
					    0)))))

;;; group-by-advertiser : list-of-plist -> list of plist
;;; One row per distinct advertiserId -- a sample location (for
;;; identifying which retailer it is at a glance), how many separate
;;; <catalog> entries it has, and TOTAL records summed across all of
;;; them.

(defun group-by-advertiser (catalogs)
  (let ((groups (make-hash-table :test 'equal)))
    (dolist (c catalogs)
      (let* ((id (getf c :advertiser-id))
	     (existing (gethash id groups)))
	(setf (gethash id groups)
	      (list :sample-location (or (getf existing :sample-location) (getf c :location))
		    :entry-count (1+ (or (getf existing :entry-count) 0))
		    :total-records (+ (or (getf existing :total-records) 0) (getf c :num-records))))))
    (loop for id being the hash-keys of groups using (hash-value v)
	  collect (list* :advertiser-id id v))))

;;; report-new-retailers : nil -> nil
;;; Prints only advertisers NOT already in *known-advertiser-ids*,
;;; sorted by total records descending -- a Joom-scale outlier lands
;;; at the top automatically, impossible to miss.

(defun report-new-retailers ()
  (let* ((catalogs (parse-catalogs *xml-path*))
	 (groups (group-by-advertiser catalogs))
	 (new (remove-if (lambda (g) (member (getf g :advertiser-id) *known-advertiser-ids* :test #'string=))
			  groups)))
    (if new
	(dolist (g (sort new #'> :key (lambda (g) (getf g :total-records))))
	  (format t "advertiserId ~a~%  sample: ~a~%  catalog entries: ~a~%  total records: ~a~%~%"
		  (getf g :advertiser-id) (getf g :sample-location)
		  (getf g :entry-count) (getf g :total-records)))
	(format t "No new retailers found -- everything in catalogs_info_file.xml is already configured.~%"))))

(report-new-retailers)
