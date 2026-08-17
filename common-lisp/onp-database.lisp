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
	 (find-nils (cdr products) (cons (car products) buggers)))
	(T (find-nils (cdr products) buggers)))))


(defparameter *buggers* (find-nils *products*))


(defun partition (predicate list)
  (let ((yes nil)
	(no nil))
    (dolist (item list)
      (if (funcall predicate item)
	  (push item yes)
	  (push item no)))
    (values (nreverse yes)
	    (nreverse no))))

(defparameter *buggers-with-numbers* nil)
(defparameter *buggers-without-numbers* nil)

(multiple-value-setq (*buggers-with-numbers*
		      *buggers-without-numbers*)
  (partition
   (lambda (product)
     (find-if #'digit-char-p (product-name product)))
   *buggers*))


(defun match (pattern string)
  (multiple-value-bind (start end)
      (cl-ppcre:scan pattern string)
    (when start
      (subseq string start end))))


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


(defparameter *quantity-candidates*
  (remove-if-not
   (lambda (p)
     (extract-quantity-candidate (product-name p)))
   *buggers-with-numbers*))

(defparameter *quantity-unmatched*
  (remove-if
   (lambda (p)
     (extract-quantity-candidate (product-name p)))
   *buggers-with-numbers*))


(defun find-oz-case (products)
  (remove-if-not
   (lambda (p)
     (and (search " oz" (product-name p))
          (search "Case of" (product-name p))))
   products))

(defun extract-oz-case-quantity (name)
  (let ((oz-pos (search " oz" name))
        (case-pos (search "Case of" name)))
    (when (and oz-pos case-pos)
      (list
       ;; quantity before " oz"
       (subseq name
               (or (position-if
                    (lambda (c)
                      (or (digit-char-p c)
                          (char= c #\.)))
                    name :end oz-pos)
                   oz-pos)
               (+ oz-pos 3))
       ;; "Case of N"
       (let ((start (+ case-pos 8)))
         (format nil "Case of ~a"
                 (string-trim '(#\Space #\)) 
                              (subseq name start
                                      (or (position #\, name :start start)
                                          (length name))))))))))

(defun extract-oz-case (name)
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



;;: function calls

;;(mapcar #'product-name *buggers-with-numbers*)
;;(mapcar #'product-name *buggers-without-numbers*)

#|
;; weight
N oz
N lb
Noz
(N oz)
(N oz bag)
(N lb bag)
(N lb Bag)
N Cup

;; count
N Piece Set
N Unscented Bags
N pack
N month supply
Case of N
N-N Inch
N oz Bag
(N Pack)
N pack
Nct
N ct
(N Count)

;; weight and count
Noz Case of N
N oz Case of N
N oz (Case of N)
N oz ( Case of N)


;; somewhat anomolous
;; two items each with quantity
"SPOT Cat Toys, Lattice Balls 4 Pack" "SPOT Cat Toys, Mylar Ball 4 Pack"
;; non-quantity and quantity
"NaturVet Hemp Shampoo & Conditioner 2-in-1 for Dogs, Argan & Coconut Oil 16 oz"
;; weight and quantity but seperated
"Nulo Signature Stew Small Breed Dog Food 2.8 oz, Chicken & Sweet Potato (Case of 24) Flavor"

;; Non-quantity
100% Recycled
80's Classic
"360 Pet Nutrition Freeze Dried Liver Treats for Dogs, Chicken Flavor"
"Ruff Dawg K9 Flyer Rubber Flying Disc Dog Toy, K9 Junior Flyer, Assorted"

|#
;;; end diagnostic tools


;;; SQLite persistence

;;; Path to DB
(defparameter *db-path*
  "../database/onp.db")


;;; products.id is a SURROGATE KEY which is assigned by the DB and
;;; auto-incrementing. (supplier, sku) is a composite unique constraint
;;; within a supplier's feed. It lets a re-run of the same feed update
;;; existing rows instead of duplicating them.
(defparameter *products-columns*
  (list
   (list  "supplier" "TEXT NOT NULL" #'product-supplier)
   (list "sku" "TEXT" #'product-sku)
   (list "mpn" "TEXT" #'product-mpn)
   (list "upc" "TEXT" #'product-upc)
   (list "ean" "TEXT" #'product-ean)
   (list "name" "TEXT NOT NULL" #'product-name)
   (list "manufacturer" "TEXT" #'product-manufacturer)
   (list "original_price" "REAL" #'product-original-price)
   (list "current_price" "REAL" #'product-current-price)
   (list "discount" "REAL" #'product-discount)
   (list "discount_percent" "REAL" #'product-discount-percent)
   (list "condition" "TEXT" #'product-condition)
   (list "color" "TEXT" #'product-color)
   (list "available" "INTEGER" (lambda (p) (if (product-available? p) 1 0)))
   (list "product_url" "TEXT" #'product-product-url)
   (list "image_url" "TEXT" #'product-image-url)
   (list "description" "TEXT" #'product-description)
   (list "product_type" "TEXT" #'product-product-type)
   (list "category" "TEXT" #'product-category)
   (list "raw_quantity" "TEXT" #'product-raw-quantity)
   (list "currency" "TEXT" #'product-currency)))


;;; Handler for product id, alt-images, and alt-image position on the list.
;;; Data come from insert-product loop.
(defparameter *images-columns*
  (list
   (list "product_id" "INTEGER NOT NULL")
   (list "alt_image_url" "TEXT NOT NULL")
   (list "position" "INTEGER")))


;;; Deriving SQL from the column spec

;;; Columns->create-tale-sql : list of column-spec &optional list-of-string -> string
;;; Builds a CREATE TABLE statement from a column spec. Every table gets a surrogate
;;; `id` primary key for free; table-constraints are extra trailing clauses like
;;; UNIQUE of FOREIGN KEY.

(defun columns->create-table-sql (table-name columns &optional table-constraints)
  (let* ((column-lines
	   (mapcar (lambda (col)
		     (format nil " ~a ~a," (first col) (second col)))
		   columns))
	 (constraint-lines
	   (mapcar (lambda (c) (format nil " ~a," c)) table-constraints))
	 (body-lines
	   (append (list " id INTEGER PRIMARY KEY AUTOINCREMENT,")
		   column-lines
		   constraint-lines)))
    ;; the last line can't have a trailing comma
    (setf (car (last body-lines))
	  (string-right-trim "," (car (last body-lines))))
    (format nil "CREATE TABLE IF NOT EXISTS ~a (~%~{~a~%~});"
	    table-name body-lines)))


;;; columns->insert-sql : string list-of-column-spec -> string
;;; Builds "INSERT OR REPLACE INTO table (a, b, c) VALUES (?,?,?)"
;;; with column order and placeholder count read straight off the
;;; same spec -- there's no way for these two to disagree.

(defun columns->insert-sql (table-name columns)
  (let ((names (mapcar #'first columns)))
    (format nil "INSERT OR REPLACE INTO ~a (~{~a~^, ~}) VALUES (~{~a~^,~})"
	    table-name
	    names
	    (make-list (length names) :initial-element "?"))))


(defparameter *create-products-sql*
  (columns->create-table-sql "products" *products-columns*
			     (list "UNIQUE (supplier, sku)")))


(defparameter *create-images-sql*
  (columns->create-table-sql "product_images" *images-columns*
			     (list "FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE")))


(defparameter *insert-product-sql*
  (columns->insert-sql "products" *products-columns*))


;;; init-db : sqlite-handle -> nil
;;; Creates both tables (if needed), enables foreign key enforcement -- off by default in
;;; SQLite -- and adds lookup indexes on the identity columns you'll actually query/match
;;; on later (mpn/upc/ean for cross-supplier matching, sku for supplier-scoped lookup).

(defun init-db (db)
  (sqlite:execute-non-query db "PRAGMA foreign_keys = ON;")
  (sqlite:execute-non-query db *create-products-sql*)
  (sqlite:execute-non-query db *create-images-sql*)
  (sqlite:execute-non-query db "CREATE INDEX IF NOT EXISTS idx_products_mpn ON products(mpn);")
  (sqlite:execute-non-query db "CREATE INDEX IF NOT EXISTS idx_products_upc ON products(upc);")
  (sqlite:execute-non-query db "CREATE INDEX IF NOT EXISTS idx_products_ean ON products(ean);")
  (sqlite:execute-non-query db "CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);")
  (sqlite:execute-non-query db "CREATE INDEX IF NOT EXISTS idx_images_product_id ON product_images(product_id);"))


;;; Insert

;;; Insert-product : sqlite-handle product -> nil
;;; Writes one product row keyed on (supplier, sku), pulling every value by calling the
;;; accessor stored next to its column in *products-columns*. Then writes the image rows
;;; keyed on the surrogate id SQLite assigned. ON DELETE CASCADE on product_images means
;;; if INSERT OR REPLACE swaps out a conflicting products row (which deletes-then-reinserts
;;; under the hood, generating a *new* id), the old row's orphaned images get cleaned up
;;; automatically rather than piling up as garbage.

(defun insert-product (db product)
  (apply #'sqlite:execute-non-query db *insert-product-sql*
	 (mapcar (lambda (col) (funcall (third col) product))
		 *products-columns*))

  (let ((product-id (sqlite:last-insert-rowid db)))
    (loop for img in (product-alt-images product)
	  for pos from 1
	  when img
	    do (sqlite:execute-non-query db
					 "INSERT INTO product_images (product_id, alt_image_url, position) VALUES (?,?,?)"
					 product-id img pos))))


;;; load-products-to-db : list-of products [db-path] -> nil
;;; Opens the database, ensures the schema exists, and inserts every product.
(defun load-products-to-db (products &optional (db-path *db-path*))
  (sqlite:with-open-database (db db-path)
    (init-db db)
    (sqlite:with-transaction db
      (dolist (p products)
	(insert-product db p))))
  (format t "~&Loaded ~a products into ~a~%" (length products) db-path))




