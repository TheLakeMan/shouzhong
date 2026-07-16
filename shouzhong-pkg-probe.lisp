;;; shouzhong-pkg-probe.lisp — proves shouzhong is a valid, cwd-independent package.
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; run_tests.sh copies shouzhong into a throwaway $HOME/.rusty/packages/shouzhong
;;; and runs this from an UNRELATED working directory. It checks three things
;;; without pkg.lisp, an LLM, or the network:
;;;   MANIFEST-OK        — package.lisp reads as a well-formed manifest
;;;   PKG-ENTRY-OK       — loading the manifest's `main` brings the framework up
;;;                        despite cwd-relative `load`
;;;   SELFCHECK-GUARDED  — shouzhong-self-check degrades (no crash) without pkg.lisp

(define pkgdir (string-append (shell "printf $HOME") "/.rusty/packages/shouzhong"))

;; (1) Manifest well-formed — read as pkg-read-manifest does, without pkg.lisp.
(define manifest
  (eval-string
    (string-append "(quote " (file-read (string-append pkgdir "/package.lisp")) ")")))
(define (m-get k) (let ((h (assoc k manifest))) (if h (cadr h) #f)))
(println
  (if (and (equal? "shouzhong" (m-get 'name))
           (string? (m-get 'version))
           (equal? "shouzhong-pkg.lisp" (m-get 'main)))
    "MANIFEST-OK" "MANIFEST-FAIL"))

;; (2) The package entry loads the certify framework from this foreign cwd.
(load (string-append pkgdir "/shouzhong-pkg.lisp"))
(define fn-type (type-of (lambda (x) x)))
(println
  (try-catch
    (if (and (equal? fn-type (type-of certify-plant))    ; shouzhong.lisp loaded
             (equal? fn-type (type-of certify-report)))   ; shouzhong.lisp loaded
      "PKG-ENTRY-OK" "PKG-ENTRY-FAIL")
    (e) "PKG-ENTRY-FAIL"))

;; (3) Self-check degrades, not crashes, outside a real pkg-install:
;;     Rusty <0.49 has no pkg.lisp loaded -> 'pkg-not-loaded; Rusty >=0.49
;;     embeds pkg.lisp, so pkg-drift runs and honestly reports this
;;     copied-not-installed package as 'no-lock. Both are graceful.
(println
  (try-catch
    (if (member (car (shouzhong-self-check)) '(pkg-not-loaded no-lock))
      "SELFCHECK-GUARDED-OK" "SELFCHECK-GUARDED-FAIL")
    (e) "SELFCHECK-GUARDED-FAIL"))
