;;; convert-ir-to-csv.lisp
;;;
;;; Converts the tab-delimited Impact Radius (IR) catalog export into
;;; the comma-delimited CSV that catalog.lisp actually reads
;;; (*impact-catalog* points at a .csv, not the raw feed).
;;;
;;; Uses cl-csv for both the read and the write side -- same library
;;; catalog.lisp already loads. This isn't just a delimiter swap:
;;; Product Description fields in this feed are HTML containing real
;;; commas ("antioxidants, vitamins, and key nutrients"). A naive
;;; tr/sed character substitution would silently shift every field
;;; after a comma into the wrong column, with no error anywhere.
;;; cl-csv's writer quotes any field that needs it (contains the
;;; delimiter, a quote character, or a newline) and escapes embedded
;;; quotes -- which is the actual job a CSV writer exists to do.
;;;
;;; Usage:
;;;   sbcl --script convert-ir-to-csv.lisp INPUT.txt OUTPUT.csv

;; --script mode disables init file loading (--no-sysinit --no-userinit),
;; so ~/.sbclrc never runs -- which is normally where Quicklisp gets
;; bootstrapped. Load it explicitly instead of depending on that, since
;; a cron-invoked script shouldn't rely on interactive shell setup anyway.
;;
;; This has to be its OWN top-level form, separate from the quickload
;; call below. LOAD reads and evaluates one top-level form at a time --
;; but READ parses an entire form, including every symbol in it, before
;; evaluation of any part of that form begins. If `load quicklisp-setup`
;; and `ql:quickload` sat inside the same form, the reader would choke
;; trying to parse the literal text "ql:quickload" -- which requires the
;; QL package to already exist just to tokenize it -- before the `load`
;; that would have created that package ever got a chance to run.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (let ((quicklisp-setup (merge-pathnames "quicklisp/setup.lisp"
                                           (user-homedir-pathname))))
    (if (probe-file quicklisp-setup)
        (load quicklisp-setup)
        (error "Quicklisp not found at ~a -- if it's installed somewhere else, update this path." quicklisp-setup))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload :cl-csv :silent t))

;;; convert-ir-to-csv : input-path output-path -> nil
;;; Streams the conversion row by row rather than reading the whole
;;; file into memory first -- matches the pattern load-delimited
;;; already uses in catalog.lisp, and scales fine regardless of how
;;; large the feed grows.

(defun convert-ir-to-csv (input-path output-path)
  (with-open-file (in input-path :direction :input)
    (with-open-file (out output-path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
      (let ((row-count 0))
        (loop
          for row = (handler-case
                        (cl-csv:read-csv-row in :separator #\Tab)
                      (end-of-file () nil))
          while row
          do (cl-csv:write-csv-row row :stream out :separator #\,)
             (incf row-count))
        (format t "~&Converted ~a rows: ~a -> ~a~%"
                row-count input-path output-path)))))

;; Run directly when invoked as: sbcl --script convert-ir-to-csv.lisp in out
(let ((args (rest sb-ext:*posix-argv*)))
  (if (= (length args) 2)
      (convert-ir-to-csv (first args) (second args))
      (progn
        (format t "~&Usage: sbcl --script convert-ir-to-csv.lisp INPUT.txt OUTPUT.csv~%")
        (sb-ext:exit :code 1))))
