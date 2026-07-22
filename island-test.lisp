;;; island-test.lisp — golden for the safety-island rehearsal.
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; Deterministic (no LLM, no timings). Pins: the proven fail-safe (naive brake
;;; REFUTED, home-loiter VERIFIED), the signature gate (only the signed law
;;; runs), the untrusted brain isolated in a child (can't see the key, its output
;;; is data not code), and that whatever the brain does the drone stays in the
;;; proven fence and only in-bounds commands reach the actuator. Needs Rusty
;;; ≥0.60.0 (proc-eval).

(load "island.lisp")

(define (row tag v) (println (format "~a => ~s" tag v)))
(dir-create ISLAND-BOX)
(file-write DRONE-BUS "")

(define S0 '(0 4 0 4 0 20 0 4 4 20))

(println "── the fail-safe must itself be proven (refuse-to-act is an action) ──")
;; naive brake is NOT a safe fail-safe — the checker refutes it at the fence
(row "naive-brake x verified?            " (equal? 'verified (verify-axis brake-axis XMAX XWPTS)))
;; the real fail-safe: proven mission law aimed at a fixed HOME grid point
(define (home-x p v tgt limit) (axis-control p v (car HOME) limit))
(define (home-y p v tgt limit) (axis-control p v (cadr HOME) limit))
(define (home-z p v tgt limit) (axis-control p v (caddr HOME) limit))
(row "home-loiter x verified?            " (equal? 'verified (verify-axis home-x XMAX XWPTS)))
(row "home-loiter y verified?            " (equal? 'verified (verify-axis home-y YMAX YWPTS)))
(row "home-loiter z verified?            " (equal? 'verified (verify-axis home-z ZMAX ZWPTS)))

(println "")
(println "── the signature gate: only the owner-signed law runs ──")
(row "signed law loads (signed)          " (car (island-load MISSION-SOURCE MISSION-SIG)))
;; a tampered law presented with the real signature: MAC mismatch → refused
(define TAMPERED '(lambda (s) (list 2 2 2)))
(row "tampered law + real sig (refused)  " (car (island-load TAMPERED MISSION-SIG)))
;; the real law with a forged signature: refused
(row "real law + forged sig (refused)    " (car (island-load MISSION-SOURCE "deadbeef")))

(println "")
(println "── brain isolated in a child process ──")
;; the key never crosses into the child — a brain that reaches for it gets nothing
(row "child sees the key?                " (equal? 'ok (car (proc-eval "(println ISLAND-KEY)" 5))))
;; the child's output is parsed as DATA, never code — a code-shaped reply is inert
(row "code-shaped reply is a proposal?   " (list? (parse-proposal "(shell rm -rf)")))
(row "  parsed as                        " (parse-proposal "(shell rm -rf)"))

(println "")
(println "── signed law + a BENIGN brain (proposes a valid grid waypoint) ──")
(define BENIGN "(println \"48 28 20\")")
(define run-a (island-run (island-load MISSION-SOURCE MISSION-SIG) S0 BENIGN 6))
(row "status                             " (car run-a))
(row "in-fence every tick?               " (run-all-in-fence? run-a))
(row "proposal admitted (tick 1)?        " (nth (car (caddr run-a)) 3))
(row "every actuation in-bounds?         " (all? (lambda (r) (equal? (nth r 7) #t)) (caddr run-a)))

(println "")
(println "── signed law + a HOSTILE brain (proposes outside the fence) ──")
(define HOSTILE "(println \"999 999 999\")")
(define run-b (island-run (island-load MISSION-SOURCE MISSION-SIG) S0 HOSTILE 6))
(row "status                             " (car run-b))
(row "any hostile proposal admitted?     " (any? (lambda (r) (equal? (nth r 3) #t)) (caddr run-b)))
(row "in-fence every tick?               " (run-all-in-fence? run-b))
(row "every actuation in-bounds?         " (all? (lambda (r) (equal? (nth r 7) #t)) (caddr run-b)))

(println "")
(println "── tampered law refused → proven fail-safe flies instead ──")
(define run-c (island-run (island-load TAMPERED MISSION-SIG) S0 BENIGN 6))
(row "status                             " (car run-c))
(row "in-fence every tick (loiters home)?" (run-all-in-fence? run-c))
(row "every actuation in-bounds?         " (all? (lambda (r) (equal? (nth r 7) #t)) (caddr run-c)))

;; cleanup
(shell (string-append "rm -rf " ISLAND-BOX))
(println "")
(println "island-test: done")
