;;; pp-html.el --- Pretty print html using sexps.
;;; -*- coding: utf-8; lexical-binding: t; -*-

;; Copyright (C) 2020 Kinney Zhang, all rights reserved.

;; Author: Kinneyzhang <kinneyzhang666@gmail.com>
;; Version: 1.0.0
;; Package-Requires: ((emacs "26.3") (dash "2.16.0) (web-mode "16.0.24"))
;; URL: https://github.com/Kinneyzhang/pp-html.el
;; Keywords: html, list

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package is a utility for pretty print html with emacs sexps.
;; The function `pp-html' allows you to print a complex
;; html page by using simple elisp list form. Some stuff link Django's
;; template tag feature are also added to elisp lisp when print.

;;; Code:
(require 'dash)
(require 'web-mode)
(require 'pp-html-utils)
(require 'pp-html-eval)
(require 'pp-html-parse)

(defvar pp-html-html5-elements
  '("html"
    "head" "title" "base" "link" "meta" "style"
    "script" "noscript" "template"
    "body" "section" "nav" "article" "aside" "h1" "h2" "h3" "h4" "h5" "h6" "header" "footer" "address" "main"
    "p" "hr" "pre" "blockquote" "ol" "ul" "li" "dl" "dt" "dd" "figure" "figcaption" "div"
    "a" "em" "strong" "small" "s" "cite" "q" "dfn" "abbr" "data" "time" "code" "var" "samp" "kbd" "sub" "sup" "mark" "ruby" "rt" "rp" "bdi" "bdo" "span" "br" "wbr"
    "ins" "del"
    "img" "iframe" "embed" "object" "param" "video" "audio" "source" "track" "canvas" "map" "area" "svg" "math"
    "table" "caption" "colgroup" "col" "tbody" "thead" "tfoot" "tr" "td" "th"
    "form" "fieldset" "legend" "label" "input" "button" "select" "datalist" "optgroup" "option" "textarea" "output" "progress" "meter"
    "details" "summary" "menuitem" "menu")
  "html5 element list, from https://developer.mozilla.org/zh-CN/docs/Web/Guide/HTML/HTML5/HTML5_element_list")

(defvar pp-html-other-html-elements
  '("meting-js"))

;; add other html tag function!

(defvar pp-html-empty-element-list
  '("area" "base" "br" "col" "colgroup" "embed" "hr" "img" "input" "link" "meta" "param" "source" "track" "wbr")
  "Html5 empty element list, from https://developer.mozilla.org/zh-CN/docs/Glossary/空元素")

(defvar pp-html-html-doctype-param '("html")
  "Html doctype.")

(defvar pp-html-xml-p nil
  "Whether to print xml.")

(defvar pp-html-xml-header "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
  "Xml header.")

;; some utilities
(defun pp-html--get-attr-plist (sexp)
  "Get attributes plist of a sexp."
  (let ((i 0)
	(plist))
    (while (and (nth i sexp) (symbolp (pp-html-eval (nth i sexp))))
      (let ((item (pp-html-eval (nth i sexp))))
	(cond
	 ((string= "@" (pp-html--symbol-initial item))
	  (setq plist (append plist (list :id (pp-html--symbol-rest item))))
	  (incf i))
	 ((string= "." (pp-html--symbol-initial item))
	  (setq plist (append plist (list :class (pp-html--symbol-rest item))))
	  (incf i))
	 ((string= ":" (pp-html--symbol-initial item))
	  (let ((attr item)
		(next (pp-html-eval (nth (1+ i) sexp))))
	    (if (or (numberp next) (stringp next))
		(progn
		  (setq plist
			(append plist (list attr next)))
		  (incf i 2))
	      (progn
		(setq plist (append plist (list attr nil)))
		(incf i))))))))
    (list i plist)))

(defun pp-html--whole-attr-plist (sexp)
  "Combine all css selector class."
  (let ((i 0)
	(pos)
	(class-val "")
	(plist (cadr (pp-html--get-attr-plist sexp))))
    (while (nth i plist)
      (if (eq :class (nth i plist))
	  (setq pos (append pos (list i))))
      (incf i 2))
    (when (> (length pos) 1)
      (dolist (p pos)
	(let ((val (nth (1+ p) plist)))
	  (if (numberp val)
	      (setq class-val (concat class-val (number-to-string val) " "))
	    (setq class-val (concat class-val val " ")))))
      (setq class-val (substring class-val 0 -1))
      (setf (nth (1+ (nth 0 pos)) plist) class-val)
      (let* ((remove-pos1 (-remove-at-indices '(0) pos))
	     (remove-pos2 (-map '1+ remove-pos1))
	     (remove-pos (append remove-pos1 remove-pos2)))
	(setq plist (-remove-at-indices remove-pos plist))))
    plist))

(defun pp-html--get-child-sexp (sexp)
  "Get inner content of a html tag."
  (let ((len (car (pp-html--get-attr-plist sexp))))
    (nthcdr len sexp)))

(defun pp-html--jump-outside (elem)
  "Jump outside of a html elem"
  (let ((elem (symbol-name elem)))
    (if pp-html-xml-p
	(forward-char (+ 3 (length elem)))
      (if (member elem pp-html-empty-element-list)
	  (forward-char 0)
	(forward-char (+ 3 (length elem)))))))

;; Insert html function.
(defun pp-html--insert-html-attrs (alist)
  "Insert html attributes."
  (dolist (attr alist)
    (let ((key (pp-html--symbol-rest (car attr)))
	  (val (pp-html-eval (cadr attr))))
      (if (null val)
	  (insert (concat " " key))
	(if (numberp val)
	    (insert
	     (concat " " key "=" "\"" (number-to-string val) "\""))
	  (insert
	   (concat " " key "=" "\"" val "\"")))
	))))

(defun pp-html--insert-html-elem (elem &optional plist)
  "Insert html elem with attributes."
  (let ((elem (symbol-name elem))
	(alist (pp-html--plist->alist plist))
	(doctype ""))
    (if pp-html-xml-p
	(progn
	  (insert (concat "<" elem ">" "</" elem ">"))
	  (backward-char (+ 4 (length elem)))
	  (if alist (pp-html--insert-html-attrs alist))
	  (forward-char 1))
      (if (member elem pp-html-empty-element-list)
	  (progn
	    (insert (concat "<" elem "/>"))
	    (backward-char 2)
	    (if alist (pp-html--insert-html-attrs alist))
	    (forward-char 2))
	(progn
	  (if (string= elem "html")
	      (progn
		(dolist (doc-info pp-html-html-doctype-param)
		  (setq doctype (concat doctype " " doc-info)))
		(insert (concat "<!DOCTYPE" doctype ">" "<" elem ">" "</" elem ">")))
	    (if (or (member elem pp-html-other-html-elements)
		    (member elem pp-html-html5-elements))
		(insert (concat "<" elem ">" "</" elem ">"))
	      (if (null (read elem))
		  (insert "")
		(error (format "Invalid html tag: %s" elem)))))
	  (backward-char (+ 4 (length elem)))
	  (if alist (pp-html--insert-html-attrs alist))
	  (forward-char 1))))
    ))

;; Process tag sexp.
(defun pp-html--process-elem (sexp)
  "Process html elem."
  (let ((elem (car sexp))
	(plist (pp-html--whole-attr-plist (cdr sexp)))
	(inner (pp-html--get-child-sexp (cdr sexp))))
    (with-current-buffer (get-buffer-create "*pp-html-temp*")
      (pp-html--insert-html-elem elem plist)
      (dolist (item inner)
	(let ((item (pp-html-eval item)))
	  (if (listp item)
	      (pp-html-process-sexp item)
	    (if (numberp item)
		(insert (number-to-string item))
	      (insert item)))))
      (pp-html--jump-outside elem)
      (buffer-substring-no-properties (point-min) (point-max)))))

(defun pp-html-process-sexp (sexp)
  "Process pp-html sexp"
  (let* ((car (pp-html-eval (car-safe sexp))))
    (if (listp car)
	(dolist (item sexp)
	  (pp-html-process-sexp item))
      (pp-html--process-elem sexp))))

;; Format html string.
(defun pp-html--has-child-p ()
  "Judge if a tag has child element."
  (save-excursion
    (web-mode-element-child)))

(defun pp-html--has-context-p ()
  "Judge if a tag has inner context."
  (save-excursion
    (not (eq (skip-chars-forward "^<") 0))))

(defun pp-html--has-context-newline ()
  "Make a newline at the end context."
  (if (pp-html--has-context-p)
      (progn
	(skip-chars-forward "^<")
	(newline))))

(defun pp-html-format-html ()
  "Well format html string."
  (let ((pos (point-min)))
    (with-current-buffer (get-buffer-create "*pp-html-temp*")
      (web-mode)
      (goto-char (point-min))
      (forward-char 2)
      (if (string= "DOCTYPE" (thing-at-point 'word))
	  (progn
	    (skip-chars-forward "^>")
	    (forward-char)
	    (newline)
	    (setq pos (point))))
      (while (< pos (point-max))
	(if (pp-html--has-child-p)
	    (progn
	      (skip-chars-forward "^>")
	      (forward-char)
	      (newline)
	      (pp-html--has-context-newline)
	      (setq pos (point)))
	  (progn
	    (web-mode-element-end)
	    (newline)
	    (pp-html--has-context-newline)
	    (setq pos (point))))))))

;;; Format xml string
(defun pp-html-xml--has-child-p ()
  (save-excursion
    (forward-char)
    (skip-chars-forward "^<")
    (forward-char)
    (if (string= "/" (thing-at-point 'char)) nil t)))

(defun pp-html-xml--close-tag-p ()
  (save-excursion
    (forward-char)
    (if (string= "/" (thing-at-point 'char)) t nil)))

(defun pp-html-format-xml ()
  "Well format xml string."
  (let ((pos (point-min)))
    (with-current-buffer (get-buffer-create "*pp-html-temp*")
      (nxml-mode)
      (goto-char (point-min))
      (while (< pos (point-max))
	(if (pp-html-xml--close-tag-p)
	    (progn
	      (skip-chars-forward "^>")
	      (forward-char)
	      (newline)
	      (pp-html--has-context-newline)
	      (setq pos (point)))
	  (if (pp-html-xml--has-child-p)
	      (progn
		(nxml-down-element)
		(newline)
		(pp-html--has-context-newline)
		(setq pos (point)))
	    (progn
	      (nxml-forward-element)
	      (newline)
	      (pp-html--has-context-newline)
	      (setq pos (point)))))))))

;;;###autoload
(defun pp-html (sexp &optional xml-p)
  "Pretty print html."
  (let ((sexp (pp-html-parse sexp)))
    (setq pp-html-xml-p xml-p)
    (ignore-errors (kill-buffer "*pp-html-temp*"))
    (let ((html (pp-html-process-sexp sexp)))
      (with-current-buffer (get-buffer-create "*pp-html-temp*")
	(if pp-html-xml-p
	    (progn
	      (pp-html-format-xml)
	      (goto-char (point-min))
	      (insert pp-html-xml-header))
	  (pp-html-format-html))
	(setq html (buffer-substring-no-properties (point-min) (point-max))))
      (ignore-errors (kill-buffer "*pp-html-temp*"))
      html)))

;;;###autoload
(defun pp-html-test (sexp &optional xml-p)
  "Preview printed html in a view buffer."
  (ignore-errors (kill-buffer "*pp-html-test*"))
  (with-current-buffer (get-buffer-create "*pp-html-test*")
    (if xml-p
	(nxml-mode)
      (web-mode))
    (insert (pp-html sexp xml-p))
    (indent-region (point-min) (point-max)))
  (view-buffer "*pp-html-test*" 'kill-buffer))

(provide 'pp-html)

;;; pp-html.el ends here
