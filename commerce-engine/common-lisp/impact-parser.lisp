;;; impact-parser.lisp

#|
Generic parsing for any catalog exported in Impact Radius (IR)
format -- Impact.com defines this as a fixed column schema, so the
same layout applies across every merchant on the network, not just
one retailer. Everything here is "read column N via a named
constant, transfer it onto a product struct slot" -- the
repeatable part. What's NOT here: anything tuned to one retailer's
product-naming conventions (e.g. ONP's oz/lb/Case-of quantity
heuristics) or one retailer's file paths/name -- those stay in
that retailer's own wrapper file, which calls into this one.

Uses *common-lisp-dir* if already set by an entry file
(catalogs.lisp or a retailer-specific wrapper file); falls back to self-locating if
compiled/loaded standalone (e.g. C-c C-k in this buffer directly).
|#

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload :cl-csv)
  (ql:quickload :cl-ppcre))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (boundp '*common-lisp-dir*)
    ;; Not loaded as a dependency of catalogs.lisp or a retailer wrapper --
    ;; file is being compiled/loaded directly (e.g. C-c C-k while
    ;; sitting in this buffer). Fall back to self-locating: this file
    ;; lives directly in common-lisp/, so its own directory already
    (defparameter *common-lisp-dir*
      (make-pathname :directory (pathname-directory
				  (or *compile-file-truename* *load-truename*)))))
  (load (merge-pathnames "product.lisp" *common-lisp-dir*)))


;; Column-index constants for the Impact Radius (IR) format. Verified
;; against the full header row of an actual IR export -- these are
;; the same across every IR catalog, since Impact.com standardizes
;; this layout network-wide.
(defconstant +sku+ 0)
(defconstant +name+ 1)
(defconstant +product-url+ 2)
(defconstant +image-url+ 3)
(defconstant +current-price+ 4)
(defconstant +available?+ 5)
(defconstant +condition+ 6)
(defconstant +ean+ 7)
(defconstant +upc+ 8)
(defconstant +mpn+ 10)
(defconstant +original-price+ 12)
(defconstant +manufacturer+ 15)
(defconstant +description+ 16)
(defconstant +product-type+ 17)
(defconstant +category+ 18)
(defconstant +parent-sku+ 20)
(defconstant +parent+ 21)
(defconstant +color+ 25)
(defconstant +material+ 26)
(defconstant +size+ 27)
(defconstant +size-unit+ 28)
(defconstant +product-launch+ 33)
(defconstant +alt-image1+ 39)
(defconstant +alt-image2+ 40)
(defconstant +alt-image3+ 41)
(defconstant +alt-image4+ 42)
(defconstant +alt-image5+ 43)
(defconstant +weight+ 47)
(defconstant +shipping-weight+ 49)
(defconstant +weight-unit+ 50)
(defconstant +currency+ 66)
(defconstant +labels+ 68)


;;; load-delimited : filename delimiter -> list
;;; Consumes a delimited file and delimiter and processes the file
;;; contents into a list of rows.

(defun load-delimited (filename delimiter)
  (with-open-file (stream filename)
    (loop
      for row = (handler-case
		    (cl-csv:read-csv-row stream :separator delimiter)
		  (end-of-file () nil))
      while row
      collect row)))


;;; nil-if-blank : string or nil -> string or nil
;;; Normalizes an empty string field to nil. The feed leaves blank
;;; columns as "" rather than omitting them, so "" and "genuinely no
;;; value" need to collapse to one representation -- otherwise every
;;; downstream consumer (SQL queries, display code, anything doing
;;; `if product-manufacturer`) has to special-case both forever.

(defun nil-if-blank (raw)
  (if (or (null raw) (string= raw ""))
      nil
      raw))


;;; parse-number-or-nil : string -> number or nil
;;; Consumes a raw numeric field from the feed. Blank fields are
;;; common -- not every merchant populates every column -- and
;;; read-from-string on an empty string signals an end-of-file
;;; error rather than returning anything, so blank input has to be
;;; handled explicitly instead of passed straight through.

(defun parse-number-or-nil (raw)
  (let ((value (nil-if-blank raw)))
    (when value (read-from-string value))))


;;; normalize-launch-date : string -> string or nil
;;; Consumes the feed's raw Product Launch Date in YYYYMMDD form
;;; (e.g. "20260328") and returns it as an ISO-8601 date string
;;; ("2026-03-28"). Blank or malformed input returns nil.

(defun normalize-launch-date (raw)
  (if (and raw (= (length raw) 8))
      (format nil "~a-~a-~a"
	      (subseq raw 0 4)
	      (subseq raw 4 6)
	      (subseq raw 6 8))
      nil))


;;; parse-labels : string -> list-of-string or nil
;;; Consumes the feed's raw comma-joined Labels field (e.g.
;;; "Bag,Genuine Leather,Gift For Her") and splits it into a list of
;;; individual label strings, trimmed of surrounding whitespace.
;;; Blank input returns nil.

(defun parse-labels (raw)
  (if (or (null raw) (string= raw ""))
      nil
      (mapcar (lambda (s) (string-trim " " s))
	      (cl-ppcre:split "," raw))))


;;; row-has-product-url? : row -> boolean
;;; product-url is the one field this whole pipeline can't function
;;; without. Rows missing it get skipped before a product struct is
;;; ever built, rather than flowing through as a "valid" product
;;; carrying a nil url.

(defun row-has-product-url? (row)
  (and (nil-if-blank (nth +product-url+ row)) t))


;;; row->product : row &key retailer raw-quantity-fn -> product
;;; Consumes an Impact-format catalog row and constructs a product
;;; struct. retailer and raw-quantity-fn are supplied by the caller
;;; (each retailer's own wrapper) rather than hardcoded here.
;;; raw-quantity-fn defaults to a function that always returns nil,
;;; so callers that don't have quantity heuristics can omit it safely.

(defun row->product (row &key retailer
			       (raw-quantity-fn (lambda (name) (declare (ignore name)) nil)))
  (let* ((original-price (parse-number-or-nil (nth +original-price+ row)))
	 (current-price (parse-number-or-nil (nth +current-price+ row)))
	 (discount
	   (if (and original-price current-price (< current-price original-price))
	       (- original-price current-price)
	       nil))
	 (discount-percent
	   (if discount
	       (* (/ discount original-price) 100)
	       nil))
	 (name (nil-if-blank (nth +name+ row)))
	 (avail (if (string= (nth +available?+ row) "Y") T nil)))
    (make-product
     :mpn (nil-if-blank (nth +mpn+ row))
     :upc (nil-if-blank (nth +upc+ row))
     :ean (nil-if-blank (nth +ean+ row))
     :name name
     :manufacturer (nil-if-blank (nth +manufacturer+ row))
     :original-price original-price
     :current-price current-price
     :discount discount
     :discount-percent discount-percent
     :condition (nil-if-blank (nth +condition+ row))
     :color (nil-if-blank (nth +color+ row))
     :material (nil-if-blank (nth +material+ row))
     :available? avail
     :product-url (nth +product-url+ row)
     :image-url (nil-if-blank (nth +image-url+ row))
     :alt-images (list
		  (nil-if-blank (nth +alt-image1+ row))
		  (nil-if-blank (nth +alt-image2+ row))
		  (nil-if-blank (nth +alt-image3+ row))
		  (nil-if-blank (nth +alt-image4+ row))
		  (nil-if-blank (nth +alt-image5+ row)))
     :description (nil-if-blank (nth +description+ row))
     :product-type (nil-if-blank (nth +product-type+ row))
     :category (nil-if-blank (nth +category+ row))
     :weight (parse-number-or-nil (nth +weight+ row))
     :shipping-weight (parse-number-or-nil (nth +shipping-weight+ row))
     :weight-unit (nil-if-blank (nth +weight-unit+ row))
     :size (nil-if-blank (nth +size+ row))
     :size-unit (nil-if-blank (nth +size-unit+ row))
     :raw-quantity (funcall raw-quantity-fn (or name ""))
     :product-launch (normalize-launch-date (nth +product-launch+ row))
     :currency (nil-if-blank (nth +currency+ row))
     :labels (parse-labels (nth +labels+ row))
     :sku (nil-if-blank (nth +sku+ row))
     :parent (nil-if-blank (nth +parent+ row))
     :parent-sku (nil-if-blank (nth +parent-sku+ row))
     :retailer retailer)))


;;; rows->products : rows &key retailer raw-quantity-fn -> list-of products
;;; Consumes a list of rows, converts each to a product struct via
;;; row->product, threading retailer/raw-quantity-fn through to every
;;; call, and returns the resulting products list. Rows with no
;;; product-url are dropped before row->product ever runs -- see
;;; row-has-product-url? above for why that field specifically gets
;;; gated rather than just nil-if-blank'd like everything else.

(defun rows->products (rows &key retailer
				  (raw-quantity-fn (lambda (name) (declare (ignore name)) nil))
				  (products nil) (skipped 0))
  (cond
    ((null rows)
     (when (> skipped 0)
       (format t "~&Skipped ~a row~:p with no product URL.~%" skipped))
     (reverse products))
    ((not (row-has-product-url? (car rows)))
     (rows->products (cdr rows)
		      :retailer retailer
		      :raw-quantity-fn raw-quantity-fn
		      :products products
		      :skipped (1+ skipped)))
    (T
     (rows->products (cdr rows)
		      :retailer retailer
		      :raw-quantity-fn raw-quantity-fn
		      :products (cons (row->product (car rows)
						     :retailer retailer
						     :raw-quantity-fn raw-quantity-fn)
				       products)
		      :skipped skipped))))


;;; get-indices : row -> list-of (index . value)
;;; Diagnostic helper for figuring out column constants when
;;; onboarding a new IR catalog -- pairs each value in a row with its
;;; index so you can eyeball which column is which.

(defun get-indices (row &optional (output nil) (index 0))
  (cond
    ((null row) (reverse output))
    (T (get-indices (cdr row) (cons (cons index (car row)) output) (1+ index)))))
