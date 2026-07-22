;; Rusty package manifest — format defined by pkg.lisp in the Rusty repo
;; (github.com/TheLakeMan/rusty). A package is any git repo with this file at
;; its root. To install (Rusty's pkg.lisp must be loaded first):
;;
;;   (load "pkg.lisp")
;;   (pkg-install "https://github.com/TheLakeMan/shouzhong")   ; clone + auto-lock
;;   (pkg-load "shouzhong")                                     ; the certify framework
;;
;; Pure Lisp on Rusty (>= 0.36.0 for the framework core's compiled defrust proof
;; transfer; the safety-island example island.lisp additionally needs >= 0.60.0
;; for proc-eval, so the full test suite requires >= 0.60.0); no package deps.
;; `main` is shouzhong-pkg.lisp, which loads the framework core (shouzhong.lisp)
;; by absolute path — Rusty's `load` is CWD-relative and a package is loaded from
;; an arbitrary working directory. The example plants (thermostat/corridor/
;; drone3d) and the safety-island example (island.lisp) ship in the repo but are
;; not loaded by the entry: shouzhong is the machinery to certify YOUR plant.
((name "shouzhong")
 (version "0.2.0")
 (main "shouzhong-pkg.lisp"))
