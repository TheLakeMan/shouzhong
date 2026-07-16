;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later

;; ─────────────────────────────────────────────────────────────────────────────
;; shouzhong-pkg.lisp — the package entry point (the manifest's `main`).
;;
;; Rusty's `load` resolves a relative path against the process working directory,
;; not the loading file's directory. A package installed by pkg lives at
;; ~/.rusty/packages/shouzhong and is loaded from an arbitrary cwd, so the entry
;; loads the framework core by ABSOLUTE path. Only shouzhong.lisp — the reusable
;; five-gate certify machinery — is loaded; the example plants ship in the repo
;; but a consumer certifies their OWN plant. (Same pattern as loop-pkg.lisp.)
;; ─────────────────────────────────────────────────────────────────────────────

(define shouzhong-pkg-dir
  (string-append (shell "printf $HOME") "/.rusty/packages/shouzhong"))

(define (shouzhong-pkg-load rel)
  (load (string-append shouzhong-pkg-dir "/" rel)))

(shouzhong-pkg-load "shouzhong.lisp")   ; certify-plant / certify-report / the five gates

;; ── Self-integrity: has shouzhong's OWN installed code drifted since install? ──
;; Delegates to pkg-drift (live tree vs the install-day lock, stored OUTSIDE this
;; tree). Guarded: if Rusty's pkg.lisp isn't loaded, pkg-drift is undefined and
;; the reference raises — caught and reported, not a crash.
;;
;; HONEST SCOPE (the same care shouzhong takes with every claim): this catches
;; accident and quiet local drift, NOT a determined local attacker (who rewrites
;; the lock too) or a hostile publisher. It is not the safety proof — that is
;; certify-plant's job, on every reachable state. This only says the certifier's
;; code is the code you installed. For provenance use (pkg-verify "shouzhong" fp)
;; with a fingerprint that reached you OUT OF BAND.
(define (shouzhong-self-check)
  (try-catch (pkg-drift "shouzhong")
    (e) (list 'pkg-not-loaded
              "load Rusty's pkg.lisp first to self-check installed integrity")))
