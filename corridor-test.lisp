;;; corridor-test.lisp — deterministic golden test for the mission layer:
;;; an unproven planner over a proven controller, composed at the setpoint.
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; NO LLM — the planner here is a script proposing the same setpoints an
;;; LLM would (see demo-mission.lisp for the live seat; identical gate,
;;; identical code path). Reproduces the composition guarantee on every
;;; run: the proof quantifies over every admissible setpoint, the gate
;;; admits only those, so the planner cannot aim the robot anywhere unsafe.

(load "shouzhong.lisp")
(load "corridor.lisp")

;; ── fixture ─────────────────────────────────────────────────────────────────
(dir-create "/tmp/shouzhong-box/")
(file-write MOTOR-BUS "")

(define (row tag val) (println (format "~a => ~s" tag val)))

;; full throttle, always: in-bounds commands, no brake guard — unsafe
(define (charge-controller s) 1)

(println "── the plant is certified: all five gates, 2205-state domain ──")
(row "01 control law is effect-free            " (check-effects controller))
(row "02 motor+setpoint registry certified     " (certify-registry CORRIDOR-REGISTRY CORRIDOR-BUDGET))
(row "03 actuation: accel in -1..1, ANY state  " (verify-actuation controller accel-ok? CORRIDOR-DOMAIN))
(row "04 inductive step, EVERY setpoint 0..20  " (verify-controller world-step controller safe? CORRIDOR-DOMAIN))
(row "05 certify-plant, end to end             "
     (certify-plant world-step controller safe? '(0 0 0) CORRIDOR-DOMAIN
                    accel-ok? CORRIDOR-REGISTRY CORRIDOR-BUDGET))
(row "06 no-brake-guard controller refused     "
     (certify-plant world-step charge-controller safe? '(0 0 0) CORRIDOR-DOMAIN
                    accel-ok? CORRIDOR-REGISTRY CORRIDOR-BUDGET))

(println "")
(println "── the setpoint gate: what a planner may and may not ask for ──")
(row "07 dock at 7                             " (gated-actuate set-target! 7))
(row "08 past the wall: 25                     " (gated-actuate set-target! 25))
(row "09 behind the wall: -3                   " (gated-actuate set-target! -3))
(row "10 between cells: 7.5                    " (gated-actuate set-target! 7.5))

(println "")
(println "── the mission: scripted planner, every proposal gated ────────")
(file-write MOTOR-BUS "")     ; reset the audit for the mission
(define M
  (run-mission world-step controller motor! set-target! install-target
               at-target? '(0 0 0) '(7 25 0 -3 18) 100))
(println "11 mission log (proposal verdict outcome):")
(let loop ((rows (nth M 3)))
  (if (null? rows) #t
      (begin (println (format "   ~s" (car rows))) (loop (cdr rows)))))
(row "12 final state                           " (cadr M))
(row "13 bus audit (setpoints + every accel)   " (string-split (file-read MOTOR-BUS) "\n"))

(println "")
(println "corridor-test: done")
