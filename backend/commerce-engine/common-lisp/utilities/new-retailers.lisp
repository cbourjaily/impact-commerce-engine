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
;;; worth, even at 53+ entries; update this list yourself whenever
;;; you add a retailer to GENERIC_RETAILERS (or ONP's own id, if
;;; that somehow ever changed). This list going stale is EXACTLY
;;; what happened the first time this ran after the six-retailer
;;; batch -- all six showed up as "new" again since nothing had
;;; updated this list to match. Don't repeat that: update this list
;;; in the SAME commit as any GENERIC_RETAILERS change, not later.
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
  (list "6955634" ; ONP (custom-parsed)
	"7479390" ; SinoCrafted (generic)
	"7452908" ; Terra (generic)
	"7368301" ; ARCN Home (generic)
	"7599876" ; ANRAN (generic)
	"7650847" ; Dr. Jojo Vitamins (generic)
	"7430394" ; Varla (generic)
	"7167120" ; DOWAN (generic)
	"7225567" ; DNT Optics (generic)
	"6936056" ; Hongkong Ossilee Trading -- REJECTED, see catalogs.lisp
	"6675705" ; Margovil (generic)
	"98634" ; Venus Swim (generic)
	"7001503" ; Stuhrling Original (generic)
	"7033143" ; Whiskey Darling (generic)
	"7450311" ; RVCA (generic)
	"3596386" ; GOLF Partner (generic)
	"3565235" ; Brxl (generic)
	"7091135" ; ArtZ Miami (generic)
	"7114321" ; SELFWHO (generic)
	"7599035" ; Alorair (generic)
	"7099710" ; Tetote Home (generic)
	"6268289" ; Easecoo (generic)
	"4292131" ; RedTop (generic)
	"7388520" ; Magic John (generic)
	"7417719" ; Tuttiosport (generic)
	"5252685" ; Rave Sports (generic)
	"7459432" ; Belela (generic)
	"5432839" ; EGOHOME Mattress (generic)
	"7092833" ; OutIn (generic)
	"7339666" ; AOOCCI International (generic)
	"3195031" ; GoldClub Direct (generic)
	"7121451" ; Haoqiebike (generic)
	"7465628" ; Screaming O (generic)
	"7356227" ; Tisscare (generic)
	"7422298" ; Plantifique (generic)
	"4292160" ; Dreame Yardcare (generic)
	"7348810" ; HK Beirui Trade (generic)
	"7446714" ; SunnyFeel (generic)
	"7332624" ; Upartner Technology (generic)
	"7400458" ; XTEINK (generic)
	"6897243" ; Jiehua International Trade (generic)
	"5428688" ; Fatboy Hair (generic)
	"3274582" ; Packed with Purpose (generic)
	"7371918" ; RunStar (generic)
	"7114959" ; Lilypad Paint (generic)
	"7364408" ; Aniioki eBikes (generic)
	"7193509" ; NuMe (generic)
	"7036290" ; Chef iQ (generic)
	"7510428" ; WiiM (generic)
	"7556796" ; Aigerri (generic)
	"000000" ; Example Retailer (generic)
	"7151050" ; Smart Fuel (generic)
	"7500620")) ; Signal Ring (generic)

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
