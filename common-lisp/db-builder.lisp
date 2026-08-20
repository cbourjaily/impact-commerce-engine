;;; db-builder.lisp

#|
Generic SQL-from-column-spec machinery.
A column spec is a list of (column-name sql-type &optional
accessor-fn) entries, and these two functions turn one into a
CREATE TABLE statement and an INSERT statement, respectively,
with column order and count read off the same spec so the two
can never drift apart.
|#

;;; columns->create-table-sql : string list-of-column-spec &optional list-of-string -> string
;;; Builds a CREATE TABLE statement from a column spec. Every table
;;; gets a surrogate `id` primary key; table-containts are extra
;;; trailing clauses like UNIQUE or FOREIGN KEY.

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
