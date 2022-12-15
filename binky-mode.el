;;; binky-mode.el --- Jump between points like a rabbit -*- lexical-binding: t -*-

;; Copyright (C) 2022 liuyinz

;; Author: liuyinz <liuyinz95@gmail.com>
;; Version: 0.9.0
;; Package-Requires: ((emacs "26.3"))
;; Keywords: convenience
;; Homepage: https://github.com/liuyinz/binky-mode

;; This file is not a part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides commands to jump between points in buffers and files.
;; Marked position, last jump position and recent buffers are all supported in
;; same mechanism like `point-to-register' and `register-to-point' but with an
;; enhanced experience.

;;; Code:

(require 'cl-lib)
(require 'cl-extra)
(require 'subr-x)

;;; Customize

(defgroup binky nil
  "Jump between points like a rabbit."
  :prefix "binky-"
  :group 'convenience
  :link '(url-link :tag "Repository" "https://github.com/liuyinz/binky-mode"))

(defcustom binky-mark-back ?,
  "Character used as mark to record last position before call `binky-jump'.
Any self-inserting character between ! (33) - ~ (126) is allowed to used as
mark.  Letters, digits, punctuation, etc.  If nil, disable the feature."
  :type '(choice character (const :tag "Disable back mark" nil))
  :group 'binky)

(defcustom binky-mark-quit ?q
  "Character used to quit the command and preview if exists.
Any self-inserting character between ! (33) - ~ (126) is allowed to used as
mark.  Letters, digits, punctuation, etc.  If nil, disable the feature.

\\[keyboard-quit] and <escape> are enable by default."
  :type '(choice character (const :tag "Disable quit mark" nil))
  :group 'binky)

(defcustom binky-mark-auto
  '(?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9 ?0)
  "List of printable characters to record recent used buffers.
Any self-inserting character between ! (33) - ~ (126) is allowed to used as
marks.  Letters, digits, punctuation, etc.  If nil, disable the feature."
  :type '(choice (repeat (choice (character :tag "Printable character as mark")))
                 (const :tag "Disable auto marks" nil))
  :group 'binky)

(defcustom binky-mark-overwrite nil
  "If non-nil, overwrite record with existing mark when call `binky-add'."
  :type 'boolean
  :group 'binky)


(defcustom binky-record-sort-by 'recency
  "Sorting strategy for auto marked buffers."
  :type '(choice (const :tag "Sort by recency" recency)
                 (Const :tag "Sort by frequency" frequency)
                 ;; TODO
                 ;; (const :tag "Sort by frecency" frecency)
                 ;; (const :tag "Sort by duration" duration)
                 )
  :group 'binky)

(defcustom binky-record-distance 5
  "Maxmium distance in lines count bwtween positions to be considered equal."
  :type 'integer
  :group 'binky)

(defcustom binky-record-prune nil
  "If non-nil, delete related record when buffer was killed."
  :type 'boolean
  :group 'binky)

(defcustom binky-include-regexps
  '("\\`\\*\\(scratch\\|info\\)\\*\\'")
  "List of regexps for buffer name included in `binky-auto-alist'.
For example, buffer *scratch* is always included by default."
  :type '(repeat string)
  :group 'binky)

(defcustom binky-exclude-regexps
  '("\\`\\(\\s-\\|\\*\\).*\\'")
  "List of regexps for buffer name excluded from `binky-auto-alist'.
When a buffer name matches any of the regexps, it would not be record
automatically unless it matches `binky-include-regexps'.  By default, all buffer
names start with '*' or ' ' are excluded."
  :type '(repeat string)
  :group 'binky)

(defcustom binky-exclude-modes
  '(xwidget-webkit-mode)
  "List of major modes which buffers belong to excluded from `binky-auto-alist'."
  :type '(repeat symbol)
  :group 'binky)

(defcustom binky-exclude-functions
  (list #'minibufferp)
  "List of predicates which buffers satisfy exclude from `binky-auto-alist'.
A predicate is a function with no arguments to check the `current-buffer'
and that must return non-nil to exclude it."
  :type '(repeat function)
  :group 'binky)

(defcustom binky-preview-delay 0.5
  "If non-nil, time to wait in seconds before popping up a preview window.
If nil, disable preview, unless \\[help] is pressed."
  :type '(choice number (const :tag "No preview unless requested" nil))
  :group 'binky)

(defcustom binky-preview-side 'bottom
  "Which side to popup preview buffer."
  :type '(choice (const top)
                 (const bottom)
				 (cosnt left)
				 (cosnt right))
  :group 'binky)

(defcustom binky-preview-column
  '((mark    10   4)
    (name    28  15)
    (line    10  6)
    (mode    22  nil)
    (context 0   nil))
  "List of elements (COLUMN VERTICAL HORIZONTAL) to display preview.
COLUMN is one of five parameters of record, listed in `binky-alist'
and `binky-auto-alist'.

The `mark' is column to show mark.
The `name' is column to show buffer or file name.
The `line' is column to show line number.
The `mode' is column to show major mode.
The `context' is column to show line content.

VERTICAL and HORIZONTAL are width of the COLUMN depended on
`binky-preview-side'.  VERTICAL used for `top' and `bottom',
HORIZONTAL used for `left' and `right'.
If it's is nil, then COLUMN would not be displayed.
If it's 0, the COLUMN would not be truncated.
Usually, `context' column should be at the end and not truncated."
  :type '(alist
          :key-type symbol
          :options '(mark name line mode context)
		  :value-type '(group (choice integer (const nil))
							  (choice integer (const nil))))
  :group 'binky)

(defcustom binky-preview-ellipsis ".."
  "String used to abbreviate text in preview."
  :type 'string
  :group 'binky)

(defcustom binky-preview-show-header t
  "If non-nil, showing header in preview."
  :type 'boolean
  :group 'binky)

(defcustom binky-preview-auto-first t
  "If non-nil, showing `binky-mark-auto' first in preview buffer."
  :type 'boolean
  :group 'binky)

(defcustom binky-highlight-duration 0.3
  "If non-nil, time in seconds to highlight the line operated on.
If nil, disable the highlight feature."
  :type '(choice number (const :tag "Disable highlight" nil))
  :group 'binky)

(defcustom binky-margin-string "\x2691"
  "Which string to show as margin indicator.
If nil, mark character would be used instead."
  ;; "\x2590" => "▐"
  ;; "\x2665" => "♥"
  ;; "\x2630" => "☰"
  ;; "\x2691" => "⚑"
  :type '(choice string (const :tag "Use mark character" nil))
  :group 'binky)

(defcustom binky-margin-side 'left
  "Which side to show margin indicator."
  :type '(choice (const left)
                 (const right))
  :group 'binky)

(defface binky-preview-header
  '((t :inherit font-lock-constant-face :underline t))
  "Face used to highlight the header in preview buffer."
  :group 'binky)

(defface binky-preview-column-mark-auto
  '((t :inherit font-lock-function-name-face :bold t :inverse-video nil))
  "Face used to highlight the auto mark of record in preview."
  :group 'binky)

(defface binky-preview-column-mark-back
  '((t :inherit font-lock-type-face :bold t))
  "Face used to highlight the back mark of record in preview."
  :group 'binky)

(defface binky-preview-column-mark
  '((t :inherit font-lock-keyword-face :bold t))
  "Face used to highlight the mark of record in preview."
  :group 'binky)

(defface binky-preview-column-name
  '((t :inherit default))
  "Face used to highlight the name of record in preview."
  :group 'binky)

(defface binky-preview-column-name-same
  '((t :inherit binky-preview-column-name :underline t))
  "Face used to highlight the name of record in same buffer in preview."
  :group 'binky)

(defface binky-preview-column-line
  '((t :inherit font-lock-variable-name-face))
  "Face used to highlight the line number of record in preview."
  :group 'binky)

(defface binky-preview-column-mode
  '((t :inherit font-lock-type-face))
  "Face used to highlight the major mode of record in preview."
  :group 'binky)

(defface binky-preview-shadow
  '((t :inherit font-lock-comment-face))
  "Face used to highlight whole record of killed buffers in preview."
  :group 'binky)

(defface binky-highlight-add
  '((t :inherit diff-refine-added))
  "Face used to highlight the line added to record."
  :group 'binky)

(defface binky-highlight-delete
  '((t :inherit diff-refine-removed))
  "Face used to highlight the line deleted from record."
  :group 'binky)

(defface binky-highlight-jump
  '((t :inherit highlight :extend t))
  "Face used to highlight the line jumped to."
  :group 'binky)

(defface binky-highlight-warn
  '((t :inherit warning :inverse-video t :extend t))
  "Face used to highlight the line already record."
  :group 'binky)

(defface binky-margin
  '((t :inherit binky-preview-column-mark
       :inverse-video nil))
  "Face used to highlight the mark of record in preview buffer."
  :group 'binky)

;;; Variables

(defvar binky-alist nil
  "List of records (MARK . INFO) set and updated by manual.
MARK is a lowercase letter between a-z.  INFO is a marker or a list of form
 (filename line mode context position) use to stores point information.")

(defvar binky-auto-alist nil
  "Alist of records (MARK . MARKER), set and updated automatically.")

(defvar binky-auto-toggle nil)

(defvar binky-back-record nil
  "Record of last position before `binky-jump', set and updated automatically.")

(defvar binky-frequency-timer nil
  "Timer used to automatically increase buffer frequency.")

(defvar binky-frequency-idle 3
  "Number of seconds of idle time to wait before increasing frequency.")

(defvar-local binky-frequency 0
  "Frequency of current buffer.")

(defvar binky-preview-buffer "*binky-preview*"
  "Buffer used to preview records.")

(defvar binky-debug-buffer "*binky-debug-log*"
  "Buffer used to debug.")

(defvar binky-alist-update-hook nil
  "Hook run when the variable `binky-alist' changes.")

(defvar-local binky-highlight-overlay nil
  "Overlay used to highlight the line operated on.")

(defvar binky-current-buffer nil
  "Buffer where binky command called from.")

(defvar binky-margin-spec-cache nil
  "Cache of margin indicator display string.")

(defvar-local binky-margin-width-orig nil
  "Default margin width of user setting.")

;;; Functions

(defun binky--log (&rest args)
  "Print log into `binky-debug-buffer' about ARGS.
ARGS format is as same as `format' command."
  (with-current-buffer (get-buffer-create binky-debug-buffer)
    (goto-char (point-max))
    (insert "\n")
    (insert (apply #'format args))))

(defun binky--regexp-match (lst)
  "Return non-nil if current buffer name match the LST."
  (and lst (string-match-p
            (mapconcat (lambda (x) (concat "\\(?:" x "\\)")) lst "\\|")
            (buffer-name))))

(defun binky--exclude-regexp-p ()
  "Return non-nil if current buffer name should be exclude."
  (and (not (binky--regexp-match binky-include-regexps))
       (binky--regexp-match binky-exclude-regexps)))

(defun binky--exclude-mode-p ()
  "Return non-nil if current buffer major mode should be exclude."
  (and binky-exclude-modes
       (memq mode-name binky-exclude-modes)))

(defun binky--frequency-increase ()
  "Frequency increases by 1 in after each idle."
  (cl-incf binky-frequency 1))

(defun binky--frequency-get (marker)
  "Return value of `binky-frequency' of buffer which MARKER points to."
  (or (buffer-local-value 'binky-frequency (marker-buffer marker)) 0))

(defun binky--record-normalized (record)
  "Return RECORD in normalized style (mark name line mode context position)."
  (if-let* ((info (cdr record))
            ((markerp info))
            (pos (marker-position info)))
      (with-current-buffer (marker-buffer info)
        (list (car record)
              (or buffer-file-name (buffer-name) "")
              (line-number-at-pos pos 'absolute)
              major-mode
              (save-excursion
                (goto-char info)
                (buffer-substring (line-beginning-position) (line-end-position)))
              pos))
    record))

(defun binky--record-prop-get (record prop)
  "Return the property PROP of RECORD, or nil if none."
  (let ((record (binky--record-normalized record)))
    (cl-case prop
      (mark (nth 0 record))
      (name (nth 1 record))
      (line (nth 2 record))
      (mode (nth 3 record))
      (context (nth 4 record))
      (position (nth 5 record)))))

(defun binky--record-exist-p (marker)
  "Return non-nil if MARKER' line uncoverd in records.
Only when the line MARKER has larger disatance than any"
  (cl-some (lambda (x)
             (when (markerp (cdr x))
               (<= (abs (- (binky--record-prop-get (cons nil marker) 'line)
                           (binky--record-prop-get x 'line)))
                   binky-record-distance)))
           binky-alist))

(defun binky-record-auto-update ()
  "Update `binky-auto-alist' and `binky-back-record' automatically."
  ;; delete back-record if buffer not exists
  (when (and binky-back-record
             (null (marker-buffer (cdr binky-back-record))))
    (setq binky-back-record nil))
  ;; update auto marked records
  (let* ((marks (remove binky-mark-back binky-mark-auto))
         (len (length marks))
         (result (list))
         (filters (append binky-exclude-functions
                          '(binky--exclude-mode-p
                            binky--exclude-regexp-p))))
    (when (> len 0)
      ;; remove current-buffer
      (cl-dolist (buf (nthcdr 1 (buffer-list)))
        (with-current-buffer buf
          (unless (cl-some #'funcall filters)
            (push (point-marker) result))))
      ;; delete marker duplicated with `binky-alist'
      (setq result (cl-remove-if (lambda (m)
                                   (let ((binky-record-distance 0))
                                     (binky--record-exist-p m)))
                                 result))
      (cl-case binky-record-sort-by
        (recency
         (setq result (reverse result)))
        (frequency
         (cl-sort result #'> :key #'binky--frequency-get))
        ;; TODO
        ;; (frecency ())
        ;; (duration ())
        (t nil))
      (setq binky-auto-alist (cl-mapcar (lambda (x y) (cons x y))
                                        marks
                                        result)))))

(defun binky-record-swap-out ()
  "Turn record from marker into list of properties when a buffer is killed."
  (let ((orig (copy-tree binky-alist)))
    (dolist (record binky-alist)
      (when-let* ((info (cdr record))
                  ((markerp info))
                  ((eq (marker-buffer info) (current-buffer))))

        (if (and buffer-file-name
                 (null binky-record-prune))
	        (setcdr record (cdr (binky--record-normalized record)))
          (delete record binky-alist))))
    (unless (equal orig binky-alist)
      (run-hooks 'binky-alist-update-hook))))

(defun binky-record-swap-in ()
  "Turn record from list of infos into marker when a buffer is reopened."
  (let ((orig (copy-tree binky-alist)))
    (dolist (record binky-alist)
      (when-let* ((info (cdr record))
                  ((not (markerp info)))
                  ((equal (car info) buffer-file-name)))
        (setcdr record (set-marker (make-marker) (car (last info))))))
    (unless (equal orig binky-alist)
      (run-hooks 'binky-alist-update-hook))))

(defun binky--preview-horizontal-p ()
  "Return non-nil if binky preview buffer in horizontally."
  (memq binky-preview-side '(left right)))

(defun binky--preview-column ()
  "Return alist of elements (COLUMN . WIDTH) to display preview."
  (cl-remove-if (lambda (x) (null (cdr x)))
                (mapcar (lambda (f)
  					      (cons (nth 0 f)
  						        (nth (if (binky--preview-horizontal-p) 2 1) f)))
  				        binky-preview-column)))

(defun binky--preview-extract (alist)
  "Return truncated string with selected columns according to ALIST."
  (format "%s%s\n"
          (if (binky--preview-horizontal-p) "" "  ")
		  (mapconcat
		   (lambda (x)
			 (let* ((item (car x))
					(limit (cdr x))
					(str (alist-get item alist))
					(len (length str)))
			   (if (zerop limit)
				   (substring str 0 nil)
				 (setf limit (max limit (length (symbol-name item))))
				 (and (> len limit)
                      (setf (substring str
                                       (- limit (length binky-preview-ellipsis))
                                       limit)
							binky-preview-ellipsis))
				 (setf (substring str len nil) (make-string limit 32))
				 (substring str 0 limit))))
		   (binky--preview-column) "  ")))

(defun binky--preview-propertize (record)
  "Return formatted string for RECORD in preview."
  (let ((killed (not (markerp (cdr record))))
        (record (binky--record-normalized record)))
    (cl-mapcar
     (lambda (x y)
	   (let ((column-face (intern (concat "binky-preview-column-" (symbol-name x))))
             (cond-face (cond
                         (killed 'binky-preview-shadow)
                         ((and (eq x 'mark)
							   (memq (binky--mark-type
                                      (string-to-char (substring y -1))) '(auto back)))
						  (intern (concat
                                   "binky-preview-column-mark-"
								   (symbol-name (binky--mark-type
                                                 (string-to-char (substring y -1)))))))
                         ((and (eq x 'name)
                               (equal (file-name-nondirectory
                                       (buffer-name binky-current-buffer)) y))
                          'binky-preview-column-name-same)
                         (t nil))))
         (cons x (if (or killed (facep column-face))
                     (propertize y 'face (or cond-face column-face))
				   y))))
     '(mark name line mode context)
     (list (concat "  " (single-key-description (nth 0 record)))
           (file-name-nondirectory (nth 1 record))
		   (number-to-string (nth 2 record))
		   (string-remove-suffix "-mode" (symbol-name (nth 3 record)))
		   (string-trim (nth 4 record))))))

(defun binky--preview-header ()
  "Return formatted string of header for preview."
  (binky--preview-extract
   (mapcar (lambda (x)
             (cons (car x) (propertize (symbol-name (car x))
                                       'face
                                       'binky-preview-header)))
		   (binky--preview-column))))

(defun binky-preview (&optional force)
  "Preview records of marked positions in `binky-preview-buffer'.
When there is no window currently showing the buffer or FORCE is non-nil,
popup the window on the side `binky-preview-side'."
  (let* ((auto-now (and binky-mark-auto binky-auto-alist))
         (total (remove nil
					    (cons binky-back-record
                              (if binky-preview-auto-first
                                  (append auto-now binky-alist)
							    (append binky-alist auto-now))))))
    (when (or force
			  (not (get-buffer-window binky-preview-buffer)))
	  (with-current-buffer-window
		  binky-preview-buffer
		  (cons 'display-buffer-in-side-window
				(append
				 `((dedicated . t)
				   (side      . ,binky-preview-side))
				 (if (binky--preview-horizontal-p)
					 '((window-width  . fit-window-to-buffer)
					   (preserve-size . (t . t)))
				   '((window-height . fit-window-to-buffer)
					 (preserve-size . (nil . t))))))
		  nil
		(progn
		  (setq cursor-in-non-selected-windows nil
				mode-line-format nil
				truncate-lines t)
		  (setq-local fit-window-to-buffer-horizontally t)
		  (let* ((final (mapcar #'binky--preview-propertize total))
				 (back (and binky-back-record
							(binky--preview-propertize binky-back-record)))
				 (dup (and back (rassoc (cdr back) (cdr final)))))
            (erase-buffer)
			;; insert header if non-nil
			(when (and (cl-some #'integerp (mapcar #'cdr (binky--preview-column)))
					   binky-preview-show-header)
			  (insert (binky--preview-header)))
			(when dup
			  (setf (cdar dup)
					(concat (substring (cdar back) -1)
							(substring (cdar dup) 1))))
			(mapc (lambda (record)
					(insert (binky--preview-extract record)))
				  (if dup (cdr final) final))))))))

(defun binky--highlight (cmd)
  "Highlight the line CMD operated on in `binky-highlight-duration' seconds."
  (when (and (numberp binky-highlight-duration)
		     (> binky-highlight-duration 0))
    (let ((beg (line-beginning-position))
          (end (line-beginning-position 2)))
      (if binky-highlight-overlay
          (move-overlay binky-highlight-overlay beg end)
	    (setq binky-highlight-overlay (make-overlay beg end)))
	  (overlay-put binky-highlight-overlay
                   'face
                   (intern (concat "binky-highlight-" (symbol-name cmd)))))
    (sit-for binky-highlight-duration)
    (delete-overlay binky-highlight-overlay)))

(defun binky--message (mark status)
  "Echo information about MARK according to STATUS."
  (let ((al '((illegal   . "is illegal")
              (overwrite . "exists and being overwritten")
              (exist     . "already exists")
              (non-exist . "doesn't exist"))))
    (message "Mark %s %s." (single-key-description mark) (alist-get status al))))

(defun binky--mark-type (&optional mark)
  "Return type of MARK or `last-input-event'.
The `quit' means to quit the command and preview.
The `help' means to preview records if not exist.
The `back' means to jump back last position.
The `auto' means to jump to auto marked buffers.
The `manual' means to operate on records manually.
The `delete' means to delete existing mark by uppercase."
  (let ((char (or mark last-input-event)))
    (cond
     ((memq char (cons binky-mark-quit '(?\C-g ?\C-\[ escape))) 'quit)
     ((memq char (cons help-char help-event-list)) 'help)
     ((equal char binky-mark-back) 'back)
     ((memq char binky-mark-auto) 'auto)
     ((and (characterp char) (<= 97 char 122)) 'manual)
     ((and (characterp char) (<= 65 char 90)) 'delete)
     (t nil))))

(defun binky--mark-get (mark)
  "Return INFO if (MARK . INFO) found in records, or return nil."
  (alist-get mark (append (list binky-back-record)
                          binky-alist
                          (and binky-mark-auto binky-auto-alist))))

(defun binky--mark-add (mark)
  "Add (MARK . MARKER) into records."
  (cond
   ((eq major-mode 'xwidget-webkit-mode)
    (message "%s is not allowed" major-mode))
   ((binky--record-exist-p (point-marker))
    (binky--highlight 'warn)
    (message "Record already exists."))
   ((not (eq (binky--mark-type mark) 'manual))
    (binky--message mark 'illegal))
   ((and (binky--mark-get mark) (not binky-mark-overwrite))
    (binky--highlight 'warn)
    (binky--message mark 'exist))
   (t
    (binky--highlight 'add)
    (setf (alist-get mark binky-alist) (point-marker))
    (run-hooks 'binky-alist-update-hook)
    (and binky-mark-overwrite
         (binky--message mark 'overwrite)))))

(defun binky--mark-delete (mark)
  "Delete (MARK . INFO) from `binky-alist'."
  (let* ((mark (downcase mark))
         (info (binky--mark-get mark)))
    (cond
     ((not (eq (binky--mark-type mark) 'manual))
      (binky--message mark 'illegal))
     ((null info)
      (binky--message mark 'non-exist))
     (t
      (when (markerp info)
        (save-excursion
          (with-current-buffer (marker-buffer info)
            (goto-char info)
            (binky--highlight 'delete))))
	  (setq binky-alist (assoc-delete-all mark binky-alist))
      (run-hooks 'binky-alist-update-hook)))))

(defun binky--mark-jump (mark)
  "Jump to point according to (MARK . INFO) in records."
  (if-let ((info (binky--mark-get mark))
           (last (point-marker)))
	  (progn
        (if (markerp info)
            (progn
			  (switch-to-buffer (marker-buffer info))
			  (goto-char info))
		  (find-file (car info))
		  (goto-char (car (last info))))
        (binky--highlight 'jump)
        (if (characterp binky-mark-back)
            (setq binky-back-record (cons binky-mark-back last))
		  (setq binky-back-record nil)))
    (binky--message mark 'non-exist)))

(defun binky--mark-read (prompt &optional keep-alive)
  "Read and return a MARK possibly with preview.
Prompt with the string PROMPT and  may display a window listing existing
records after `binky-preview-delay' seconds.  When KEEP-ALIVE is non-nil,
preview buffer keep alive.

If `help-char' (or a member of `help-event-list') is pressed, display preview
window regardless.  Press \\[keyboard-quit] to quit."
  (setq binky-current-buffer (current-buffer))
  (and keep-alive (binky-preview 'force))
  (let ((timer (when (numberp binky-preview-delay)
		         (run-with-timer binky-preview-delay nil #'binky-preview))))
    (unwind-protect
        (progn
		  (while (memq (binky--mark-type
					    (read-key (propertize prompt 'face 'minibuffer-prompt)))
                       '(help nil))
            (and (eq (binky--mark-type) 'help) (binky-preview)))
		  (if (eq (binky--mark-type) 'quit)
              (keyboard-quit)
            last-input-event))
	  (and (timerp timer) (cancel-timer timer))
      (when (or (eq (binky--mark-type) 'quit)
                (null keep-alive))
	    (let* ((buf binky-preview-buffer)
               (win (get-buffer-window buf)))
          (and (window-live-p win) (delete-window win))
          (and (get-buffer buf) (kill-buffer buf)))))))

(defun binky--margin-spec (&optional mark)
  "Genrate and return margin display string according to MARK if provided."
  (or (and binky-margin-string binky-margin-spec-cache)
      (setq binky-margin-spec-cache
            (propertize
             " "
             'display
             `((margin ,(intern (format "%s-margin"
                                        binky-margin-side)))
               ,(propertize (or binky-margin-string (char-to-string mark))
                            'face 'binky-margin))))))

(defun binky--margin-remove (&optional beg end)
  "Remove binky overlays between BEG and END.
BEG and END default respectively to the beginning and end of the buffer."
  (save-restriction
    (widen)
    (dolist (o (overlays-in (or beg (point-min)) (or end (point-max))))
      (when (overlay-get o 'binky) (delete-overlay o)))))

(defun binky-margin-update ()
  "Update margin indicators if needed.
If variable `binky-margin-mode' or variable `binky-mode' is nil, delete all."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      ;; delete overlays
      (binky--margin-remove)
      (and binky-mode binky-margin-mode
           (or binky-margin-local-mode (binky-margin-local-mode 1)))))
  (when (and binky-mode binky-margin-mode)
    ;; update overlays
    (mapc (lambda (x)
            (let ((mark (car x))
                  (buf (marker-buffer (cdr x)))
                  (pos (marker-position (cdr x))))
              (with-current-buffer buf
                (let ((ov (make-overlay pos pos)))
                  (overlay-put ov 'binky t)
                  (overlay-put ov 'before-string (binky--margin-spec mark))))))
          (cl-remove-if-not (lambda (x) (markerp (cdr x))) binky-alist))))

;;; Commands

;;;###autoload
(defun binky-auto-toggle ()
  "Toggle whether enable auto mark feature or not."
  (interactive)
  (if binky-mark-auto
      (setq binky-auto-toggle binky-mark-auto
            binky-mark-auto nil)
    (setq binky-mark-auto binky-auto-toggle
          binky-auto-toggle nil)))

;;;###autoload
(defun binky-add (mark)
  "Add the record in current point with MARK."
  (interactive (list (binky--mark-read "Mark add: ")))
  (binky--mark-add mark))

;;;###autoload
(defun binky-delete (mark)
  "Delete the record according to MARK."
  (interactive (list (binky--mark-read "Mark delete: ")))
  (binky--mark-delete mark))

;;;###autoload
(defun binky-jump (mark)
  "Jump to point according to record of MARK."
  (interactive (list (binky--mark-read "Mark jump: ")))
  (binky--mark-jump mark))

;;;###autoload
(defun binky-binky (mark &optional keep-alive)
  "Add, delete or jump records with MARK in one command.

If MARK exists, then call `binky-jump'.
If MARK doesn't exist, then call `binky-add'.
If MARK is uppercase, and the lowercase exists, then call `binky-delete'.

Interactively, KEEP-ALIVE is the prefix argument.  With no prefix argument,
it works as same as single command.  With a prefix argument, preview the
records with no delay and keep alive until \\[keyboard-quit] pressed."
  (interactive (list (binky--mark-read "Mark: " current-prefix-arg)
                     current-prefix-arg))
  (if (binky--mark-get mark)
	  (binky--mark-jump mark)
    (if (eq (binky--mark-type mark) 'manual)
        (binky--mark-add mark)
      (binky--mark-delete mark)))
  (when keep-alive
    (binky-preview 'force)
    (call-interactively #'binky-binky)))

;;;###autoload
(define-minor-mode binky-mode
  "Toggle rabbit-jumping style position changes.
This global minor mode allows you to jump easily between buffers
you used and marked position."
  :group 'binky
  :global t
  (if binky-mode
	  (progn
        (add-hook 'buffer-list-update-hook #'binky-record-auto-update)
        (add-hook 'kill-buffer-hook #'binky-record-swap-out)
        (add-hook 'find-file-hook #'binky-record-swap-in)
        (when (eq binky-record-sort-by 'frequency)
          (setq binky-frequency-timer
			    (run-with-idle-timer binky-frequency-idle
								     t #'binky--frequency-increase))))
    (remove-hook 'buffer-list-update-hook #'binky-record-auto-update)
    (remove-hook 'kill-buffer-hook #'binky-record-swap-out)
    (remove-hook 'find-file-hook #'binky-record-swap-in)
    (when (eq binky-record-sort-by 'frequency)
      (cancel-timer binky-frequency-timer)
      (setq binky-frequency-timer nil))))

;;;###autoload
(define-minor-mode binky-margin-mode
  "Toggle displaying indicator on the margin."
  :group 'binky
  :lighter ""
  :global t
  (if binky-margin-mode
      (progn
        (add-hook 'binky-alist-update-hook #'binky-margin-update)
        (add-hook 'binky-mode-hook #'binky-margin-update))
    (remove-hook 'binky-alist-update-hook #'binky-margin-update)
    (remove-hook 'binky-mode-hook #'binky-margin-update))
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (binky-margin-local-mode (if binky-margin-mode 1 -1))))
  (binky-margin-update))

;;;###autoload
(define-minor-mode binky-margin-local-mode
  "Toggle displaying indicators on the margin locally.
You probably shouldn't use this function directly."
  :group 'binky
  :lighter ""
  (let ((width-var (intern (format "%s-margin-width" binky-margin-side))))
    (if binky-margin-local-mode
        (progn
          (setq-local binky-margin-width-orig width-var)
          (setq width-var 1))
      (setq width-var binky-margin-width-orig)
      (setq binky-margin-width-orig nil)))
  (dolist (win (get-buffer-window-list))
    (set-window-buffer win (current-buffer))))
(put 'binky-margin-local-mode 'completion-predicate #'ignore)

(provide 'binky-mode)
;;; binky-mode.el ends here
