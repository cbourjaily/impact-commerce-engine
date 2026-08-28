;;; catalogs.lisp

#|
Home for every retailer whose Impact-format catalog needs NO
retailer-specific parsing.

To add a retailer: add one (defparameter *...-catalog*) for
its file path, and one (defun load-...), following the existing
patern.
|#

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *catalogs-dir*
    (make-pathname :directory (pathname-directory
				(or *compile-file-truename* *load-truename*))))
  (defparameter *common-lisp-dir*
    (merge-pathnames "../" *catalogs-dir*))
  (load (merge-pathnames "throughput/impact-parser.lisp" *common-lisp-dir*)))


;;; Shared database -- the (retailer, sku) uniqueness constraint on products
;;; suppotrs multiple retailers writing into one database without colliding,
;;; even if two retailers happen to reuse the same sku string.

(defparameter *catalogs-db-path*
  (merge-pathnames "../../database/impact.db" *catalogs-dir*))


;;; load-catalog : retailer catalog-path &optional db-path -> list-of failures
;;; Reads an Impact-format catalog file (tab-delimited, matching the raw feed,
;;; parses it into products with no retailer-specific raw-quantity extraction,
;;; and loads the result into the shared database.

(defun load-catalog (retailer catalog-path &optional (db-path *catalogs-db-path*))
  (let* ((rows (load-delimited catalog-path #\Tab))
	 (products (rows->products (cdr rows) :retailer retailer)))
    (load-products-to-db products db-path)))


;;; ---------------------------------------------------------------
;;; Retailers -- add new ones below, following this pattern.
;;; ---------------------------------------------------------------

;;; SinoCrafted
 
(defparameter *sinocrafted-catalog*
  (merge-pathnames "../../data/sinocrafted/impact-format/Updated-sinocrafted_IR.txt"
		    *catalogs-dir*))
 
(defun load-sinocrafted ()
  (load-catalog "SinoCrafted" *sinocrafted-catalog*))
 
 
;;; Terra
 
(defparameter *terra-catalog*
  (merge-pathnames "../../data/terra/impact-format/Updated-terra_IR.txt"
		    *catalogs-dir*))
 
(defun load-terra ()
  (load-catalog "Terra" *terra-catalog*))


;;; ARCN Home

(defparameter *arcn-home-catalog*
  (merge-pathnames "../../data/arcn-home/impact-format/Updated-arcn-home_IR.txt"
		    *catalogs-dir*))

(defun load-arcn-home ()
  (load-catalog "ARCN Home" *arcn-home-catalog*))


;;; ANRAN

(defparameter *anran-catalog*
  (merge-pathnames "../../data/anran/impact-format/Updated-anran_IR.txt"
		    *catalogs-dir*))

(defun load-anran ()
  (load-catalog "ANRAN" *anran-catalog*))


;;; Dr. Jojo Vitamins

(defparameter *dr-jojo-vitamins-catalog*
  (merge-pathnames "../../data/dr-jojo-vitamins/impact-format/Updated-dr-jojo-vitamins_IR.txt"
		    *catalogs-dir*))

(defun load-dr-jojo-vitamins ()
  (load-catalog "Dr. Jojo Vitamins" *dr-jojo-vitamins-catalog*))


;;; Varla -- Impact directory is "Varla-Amazon" (Amazon-sourced
;;; catalog, unlike the Shopify-sourced ones above/below), but the
;;; retailer itself is just Varla -- dir-name kept as varla-amazon
;;; to match the shell script's GENERIC_RETAILERS entry exactly.

(defparameter *varla-amazon-catalog*
  (merge-pathnames "../../data/varla-amazon/impact-format/Updated-varla-amazon_IR.txt"
		    *catalogs-dir*))

(defun load-varla-amazon ()
  (load-catalog "Varla" *varla-amazon-catalog*))


;;; DOWAN -- Impact's own directory name includes Chinese characters
;;; (DOWAN-LLC-内容产出者); dir-name here is plain ASCII ("dowan") by
;;; deliberate choice, since this is OUR OWN local storage naming,
;;; not something that needs to match Impact's remote directory
;;; structure.

(defparameter *dowan-catalog*
  (merge-pathnames "../../data/dowan/impact-format/Updated-dowan_IR.txt"
		    *catalogs-dir*))

(defun load-dowan ()
  (load-catalog "DOWAN" *dowan-catalog*))


;;; DNT Optics

(defparameter *dnt-optics-catalog*
  (merge-pathnames "../../data/dnt-optics/impact-format/Updated-dnt-optics_IR.txt"
		    *catalogs-dir*))

(defun load-dnt-optics ()
  (load-catalog "DNT Optics" *dnt-optics-catalog*))


;;; load-all-generic-catalogs : nil -> nil
;;; Convenience for loading every retailer in this file in one call --
;;; handy for a manual full-refresh from the REPL. The cron script
;;; calls the individual load-* functions directly instead, so it can
;;; skip a retailer whose catalog didn't actually change that day.

(defun load-all-generic-catalogs ()
  (load-sinocrafted)
  (load-terra)
  (load-arcn-home)
  (load-anran)
  (load-dr-jojo-vitamins)
  (load-varla-amazon)
  (load-dowan)
  (load-dnt-optics)
  nil)
