;;; product.lisp

#|
Generic product datastructure and SQLite persistence. Nothing in
this file is specific to any particular catalog feed or retailer
-- any source that can produce a `product`struct instance (by
whatever parsing logic fits its own feed format) can load this
and call load-products-to-db on the result.

Depends on db-builder.lisp (loaded below) for the column-spec ->
SQL machinery.
|#

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload :sqlite))
 
(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (boundp '*common-lisp-dir*)
    ;; Not loaded as a dependency -- this file is being compiled/
    ;; loaded directly. Fall back to self-locating: product.lisp
    ;; lives directly in common-lisp/, so its own directory already
    ;; IS *common-lisp-dir*, no ../ needed.
    (defparameter *common-lisp-dir*
      (make-pathname :directory (pathname-directory
				  (or *compile-file-truename* *load-truename*)))))
  (load (merge-pathnames "db-builder.lisp" *common-lisp-dir*)))


;;; product struct foreach product instance to store in a database.
;;; Whichever parser builds a product is responsible for setting
;;; :retailer explicitly.

(defstruct product
  mpn               ; Manufacturer Part Number
  upc               ; Universal Product Code
  ean               ; European Article Number
  name
  manufacturer
  original-price
  current-price     ; if less than original-price, indicates sale
  discount          ; original-price - current-price (derived value)
  discount-percent  ; discount / original-price * 100 (derived value)
  condition         ; i.e., "New"
  color             ; i.e, "Natural"
  material
  available?        ; t or nil
  product-url
  image-url
  alt-images        ; list of secondary images
  description       ; given in html by stream
  product-type
  category
  weight            ; numeric, parsed
  shipping-weight   ; numeric, parsed
  weight-unit
  size
  size-unit
  raw-quantity      ; normalized size/quantity extracted from name
  product-launch    ; normalized ISO-8601 date string, or nil
  currency
  labels            ; list of strings -- own table, not a flat column
  sku
  parent
  parent-sku
  retailer)


;;; products.id is a SURROGATE KEY assigned by the DB, auto-incrementing.
;;; (retailer, sku) is a composite unique constraint within a retailer's
;;; feed -- it lets a re-run of the same feed update existing rows
;;; instead of duplicating them.

(defparameter *products-columns*
  (list
   (list  "retailer" "TEXT NOT NULL" #'product-retailer)
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
   (list "material" "TEXT" #'product-material)
   (list "available" "INTEGER" (lambda (p) (if (product-available? p) 1 0)))
   (list "product_url" "TEXT" #'product-product-url)
   (list "image_url" "TEXT" #'product-image-url)
   (list "description" "TEXT" #'product-description)
   (list "product_type" "TEXT" #'product-product-type)
   (list "category" "TEXT" #'product-category)
   (list "weight" "REAL" #'product-weight)
   (list "shipping_weight" "REAL" #'product-shipping-weight)
   (list "weight_unit" "TEXT" #'product-weight-unit)
   (list "size" "TEXT" #'product-size)
   (list "size_unit" "TEXT" #'product-size-unit)
   (list "raw_quantity" "TEXT" #'product-raw-quantity)
   (list "product_launch" "TEXT" #'product-product-launch)
   (list "currency" "TEXT" #'product-currency)
   (list "parent" "TEXT" #'product-parent)
   (list "parent_sku" "TEXT" #'product-parent-sku)))


;;; product_images gets product_id, alt_image_url, and position from
;;; insert-product's own loop rather than one accessor per column, so
;;; this spec only needs name+type, no accessor slot.

(defparameter *images-columns*
  (list
   (list "product_id" "INTEGER NOT NULL")
   (list "alt_image_url" "TEXT NOT NULL")
   (list "position" "INTEGER")))


;;; product_labels -- same shape/reasoning as product_images: Labels
;;; is a variable-count bag of same-role tag strings in the feed, so
;;; it gets its own table rather than a flat comma-joined column, the
;;; same way alt-images did. No position column -- unlike images.

(defparameter *labels-columns*
  (list
   (list "product_id" "INTEGER NOT NULL")
   (list "label" "TEXT NOT NULL")))
 
 
(defparameter *create-products-sql*
  (columns->create-table-sql "products" *products-columns*
			     (list "UNIQUE (retailer, sku)")))
 
(defparameter *create-images-sql*
  (columns->create-table-sql "product_images" *images-columns*
			     (list "FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE")))
 
(defparameter *create-labels-sql*
  (columns->create-table-sql "product_labels" *labels-columns*
			     (list "FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE")))
 
(defparameter *insert-product-sql*
  (columns->insert-sql "products" *products-columns*))


;;; *db-path* is deliberately declared here with no real value --
;;; which database file to write to is a per-catalog-source decision.
;;; Callers are expected to set this before calling load-products-to-db.

(defvar *db-path* nil)


;;; init-db : sqlite-handle -> nil
;;; Creates all three tables (if needed), enables foreign key enforcement
;;; -- off by default in SQLite -- and adds lookup indexes on the identity
;;; columns likely to get queried/matched on later (mpn/upc/ean for
;;; cross-retailer matching, sku for retailer-scoped lookup, label for
;;; "find products with tag X").

(defun init-db (db)
  (sqlite:execute-non-query db "PRAGMA foreign_keys = ON;")
  (sqlite:execute-non-query db *create-products-sql*)
  (sqlite:execute-non-query db *create-images-sql*)
  (sqlite:execute-non-query db *create-labels-sql*)
  (sqlite:execute-non-query db "CREATE INDEX IF NOT EXISTS idx_products_mpn ON products(mpn);")
  (sqlite:execute-non-query db "CREATE INDEX IF NOT EXISTS idx_products_upc ON products(upc);")
  (sqlite:execute-non-query db "CREATE INDEX IF NOT EXISTS idx_products_ean ON products(ean);")
  (sqlite:execute-non-query db "CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);")
  (sqlite:execute-non-query db "CREATE INDEX IF NOT EXISTS idx_images_product_id ON product_images(product_id);")
  (sqlite:execute-non-query db "CREATE INDEX IF NOT EXISTS idx_labels_product_id ON product_labels(product_id);")
  (sqlite:execute-non-query db "CREATE INDEX IF NOT EXISTS idx_labels_label ON product_labels(label);"))


;;; insert-product : sqlite-handle product -> nil
;;; Writes one product row keyed on (retailer, sku), pulling every
;;; value by calling the accessor stored next to its column in
;;; *products-columns*. Then writes the image rows keyed on the
;;; surrogate id SQLite assigned. ON DELETE CASCADE on both child 
;;; tables means if INSERT OR REPLACE swaps out a conflicting products
;;; row (which deletes-then-reinserts under the hood, generating a
;;; *new* id), the old row's orphaned children get cleaned up
;;; automatically.

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
					 product-id img pos))
    (loop for label in (product-labels product)
	  when (and label (not (string= label "")))
	    do (sqlite:execute-non-query db
					 "INSERT INTO product_labels (product_id, label) VALUES (?,?)"
					 product-id label))))


;;; *excluded-categories* : list of string
;;; Categories that never belong in the catalog regardless of
;;; retailer -- checkout add-ons/service items that come through
;;; retailer feeds tagged as if they were real products (shipping
;;; insurance, purchase protection, etc), not anything a shopper
;;; would search for or want to see as a search result. Confirmed
;;; directly, not guessed: SEEL-WFP (Seel's "Worry-Free Purchase"
;;; protection, SinoCrafted) and shipping-protection (xCotton's
;;; shipping insurance, also SinoCrafted, riding along under a
;;; misleading "xcotton" brand tag that isn't a real product brand
;;; at all -- confirmed directly: filtering to brand=xcotton alone
;;; returns 99 results, 100% of them this same junk).
;;;
;;; Checked ONCE here, not per-retailer -- this is the one
;;; chokepoint every retailer's pipeline funnels through (generic
;;; retailers AND ONP's own custom pipeline both call
;;; load-products-to-db directly), so adding a category here
;;; excludes it automatically for every current AND future retailer,
;;; with no per-retailer logic needed. Add a category string here
;;; whenever something like this shows up again -- that's the whole
;;; cost of extending this.
;;;
;;; Exact string match against the category column as stored -- both
;;; confirmed junk categories are flat values with no breadcrumb
;;; nesting (unlike a normal product's "A > B > C" category), so this
;;; is correct for what's actually been seen. If a future junk
;;; category ever shows up NESTED inside a real breadcrumb instead of
;;; as a flat value, exact match won't catch it -- worth knowing, not
;;; yet a real problem since nothing like that has occurred.

(defparameter *excluded-categories*
  '("SEEL-WFP" "shipping-protection"))


;;; load-products-to-db : list-of products [db-path] -> list-of failures
;;; Opens the database, ensures the schema exists, and inserts every
;;; product NOT in *excluded-categories* (see that variable's own
;;; comment for why the filter lives here). Excluded products are
;;; counted and logged SEPARATELY from failures below -- being
;;; filtered out on purpose is not the same thing as a row failing
;;; to insert, and conflating the two in the log would make a
;;; correctly-working exclusion look like something went wrong.
;;;
;;; A single row failing (e.g. a NOT NULL violation on name or sku
;;; after nil-if-blank turned an empty string into a real nil)
;;; doesn't abort the whole load -- handler-case catches inside the
;;; dolist body, so with-transaction never sees an unhandled
;;; condition and still commits everything that DID succeed. Returns
;;; the list of (product . condition) failures so the caller can
;;; inspect what got skipped and why, in addition to the printed log.

(defun load-products-to-db (products &optional (db-path *db-path*))
  (let* ((included (remove-if (lambda (p) (member (product-category p) *excluded-categories* :test #'string=))
			       products))
	 (excluded-count (- (length products) (length included)))
	 (failures nil))
    (sqlite:with-open-database (db db-path)
      (init-db db)
      (sqlite:with-transaction db
	(dolist (p included)
	  (handler-case
	      (insert-product db p)
	    (error (e)
	      (push (cons p e) failures)
	      (format t "~&SKIPPED product (retailer=~a sku=~a name=~a): ~a~%"
		      (product-retailer p) (product-sku p) (product-name p) e))))))
    (format t "~&Loaded ~a products into ~a (~a skipped, ~a excluded by category filter)~%"
	    (- (length included) (length failures))
	    db-path
	    (length failures)
	    excluded-count)
    (nreverse failures)))
