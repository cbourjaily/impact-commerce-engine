(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload :cl-csv)
  (ql:quickload :sqlite))

;; Constants for referencing items in a product row from catalog stream
(defconstant +mpn+ 10)
(defconstant +upc+ 8)
(defconstant +ean+ 7)
(defconstant +name+ 1)
(defconstant +manufacturer+ 15)
(defconstant +original-price+ 12)
(defconstant +current-price+ 4)
(defconstant +condition+ 6)
(defconstant +color+ 25)
(defconstant +available?+ 5)
(defconstant +product-url+ 2)
(defconstant +image-url+ 3)
(defconstant +alt-image1+ 39)
(defconstant +alt-image2+ 40)
(defconstant +alt-image3+ 41)
(defconstant +alt-image4+ 42)
(defconstant +alt-image5+ 43)
(defconstant +description+ 16)
(defconstant +product-type+ 17)
(defconstant +category+ 18)
(defconstant +currency+ 66)
(defconstant +sku+ 0)


;;; product struct for each product instance to store in a database.

(defstruct product
  mpn               ; Manufacturer Part Number
  upc               ; Universal Product Code
  ean               ; European Article Number
  name
  manufacturer      ; from impact
  original-price
  current-price     ; if less than original-price, indicates sale
  discount          ; original-price - current-price (derived value)
  discount-percent  ; discount / original-price * 100 (derived value)
  condition         ; i.e., "New"
  color             ; i.e, "Natural"
  available?        ; t or nil
  product-url
  image-url
  alt-images        ; list of up to 5 images for onp feeds
  description       ; given in html by stream
  product-type      ; ex: Dog > Health & Wellness > Supplements > Whole Food Supplements
  category          ; ex: Animals & Pet Supplies > Pet Supplies > Dog Supplies
  raw-quantity      ; trailing parenthetical from normalized name
  currency
  sku               ; Unique Merchant SKU
  (supplier "Only Natural Pet")
  )


;;; impact format CSV file of onp catalog
(defparameter *impact-catalog*
  "../data/onp/impact-format/Updated-ONP-Catalog_IR.csv")


;;; load-delimited : filname delimiter -> list
;;; Consumes a delimited file and delimter and processes the file
;;; contents into a list.

(defun load-delimited (filename delimiter)
  (with-open-file (stream filename)
    (loop
      for row = (handler-case
		    (cl-csv:read-csv-row stream :separator delimiter)
		  (end-of-file () nil))
	  while row
	  collect row)))


;;; Loaded catalog rows
(defparameter *impact-rows*
  (load-delimited *impact-catalog* #\, ))


;;; parse-raw-quantity : product-name -> string
;;; Consumes a name field of a product struct and extracts
;;; the product quantity.

(defun extract-raw-quantity (name)
  (let ((end (1- (length name))))
    (cond
      ((not (eq (aref name end) #\))) nil)
      (T
       (labels ((find-start (&optional (current end))
		  (cond
		    ((= current 0) nil)
		    ((eq
		      (aref name (1- current)) #\(
		      )
		     current)
		    (T
		     (find-start (1- current))))))
	 (let ((start (find-start)))
	   (if start
	       (subseq name start end)
	       nil)))))))


;;; row->product : row -> product
;;; Consumes a catalog row and constructs a product struct.

(defun row->product (row)
  (labels ((parse-image (url)
	     (if (string= url "")
		 nil
		 url)))
    (let* ((original-price (read-from-string (nth +original-price+ row)))
	   (current-price (read-from-string (nth +current-price+ row)))
	   (discount
	     (if (< current-price original-price)
		 (- original-price current-price)
		 nil))
	   (discount-percent
	     (if discount
		 (* (/ discount original-price) 100)
		 nil))
	   (name (nth +name+ row))
	   (avail (if (string= (nth +available?+ row) "Y") T nil)))
      (make-product
       :mpn (nth +mpn+ row)
       :upc (nth +upc+ row)
       :ean (nth +ean+ row)
       :name name
       :manufacturer (nth +manufacturer+ row)
       :original-price original-price
       :current-price current-price
       :discount discount
       :discount-percent discount-percent
       :condition (nth +condition+ row)
       :color (nth +color+ row)
       :available? avail	    
       :product-url (nth +product-url+ row)
       :image-url (nth +image-url+ row)
       :alt-images (list
		    (parse-image (nth +alt-image1+ row))
		    (parse-image (nth +alt-image2+ row))
		    (parse-image (nth +alt-image3+ row))
		    (parse-image (nth +alt-image4+ row))
		    (parse-image (nth +alt-image5+ row)))
       :description (nth +description+ row)
       :product-type (nth +product-type+ row)
       :category (nth +category+ row)
       :raw-quantity (extract-raw-quantity name)
       :currency (nth +currency+ row)
       :sku (nth +sku+ row)))))


;;; rows->products : list-of rows -> list-of products
;;; Consumes a list of rows, converts each row to a product struct,
;;; and returns the resulting products list.

(defun rows->products (rows &optional (products nil))
  (cond
    ((null rows) (reverse products))
    (T
     (rows->products (cdr rows)
		     (cons (row->product (car rows)) products)))))


;;; List of product structs
(defvar *products* (rows->products (cdr *impact-rows*)))


;;; diagnostics to explore cases of nil in raw-data field

(defun find-nils (products &optional (buggers nil))
  (if (null products) (reverse buggers)
      (cond
	((null (product-raw-quantity (car products)))
	 (find-nils (cdr products) (cons (product-name (car products)) buggers)))
	(T (find-nils (cdr products) buggers)))))


(defvar *buggers* (find-nils *products*))

;;; end diagnostic tools


;;; SQLite persistence

;;; Path to DB
(defparameter *db-path*
  "../

;;; products.id is a SURROGATE KEY which is assigned by the DB and
;;; auto-incrementing. (supplier, sku) is a composite unique constraint
;;; within a supplier's feed. It lets a re-run of the same feed update
;;; existing rows instead of duplicating them.

(defparameter *create-products-sql*
  "CREATE TABLE IF NOT EXISTS products (
