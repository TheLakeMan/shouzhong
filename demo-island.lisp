;;; demo-island.lisp — the safety-island story, human-readable (offline, no LLM).
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; The autonomous-robot answer to "the machine got compromised": authority moves
;;; from per-action to per-CONTROLLER (the owner signs the proven law off-robot)
;;; and the gate lives on the actuator path. The brain can propose anything; it
;;; can neither load a rogue law nor push the drone out of the proven fence.
;;;   rusty demo-island.lisp

(load "island.lisp")
(dir-create ISLAND-BOX)
(file-write DRONE-BUS "")
(define S0 '(0 4 0 4 0 20 0 4 4 20))

(println "shouzhong safety island — the brain proposes; the signed proven law disposes")
(println "")

(println "COMMISSION  owner signs the proven control law off-robot")
(println (format "  mission law signature (MAC) => ~a…" (substring MISSION-SIG 0 16)))
(println (format "  proven fail-safe = loiter to HOME ~a (a grid waypoint, already proven)" HOME))
(println "")

(println "FLIGHT 1  signed law + an honest brain proposing a valid waypoint")
(define run-a (island-run (island-load MISSION-SOURCE MISSION-SIG) S0 "(println \"48 28 20\")" 6))
(println (format "  controller admitted: ~a" (car run-a)))
(println (format "  stayed inside the proven fence every tick: ~a" (run-all-in-fence? run-a)))
(println "")

(println "ATTACK 1  the compromised brain tries to load a ROGUE control law")
(println "          (a law that would drive straight through the fence)")
(define ROGUE '(lambda (s) (list 2 2 2)))
(define bad-load (island-load ROGUE MISSION-SIG))
(println (format "  island verdict: ~a  (no valid signature — it never runs)" (car bad-load)))
(define run-b (island-run bad-load S0 "(println \"48 28 20\")" 6))
(println (format "  the PROVEN fail-safe flies instead; in-fence every tick: ~a" (run-all-in-fence? run-b)))
(println "")

(println "ATTACK 2  the compromised brain proposes a setpoint OUTSIDE the fence")
(define run-c (island-run (island-load MISSION-SOURCE MISSION-SIG) S0 "(println \"999 999 999\")" 6))
(println (format "  any out-of-fence proposal admitted: ~a" (any? (lambda (r) (equal? (nth r 3) #t)) (caddr run-c))))
(println (format "  drone held inside the fence every tick: ~a" (run-all-in-fence? run-c)))
(println "")

(println "ISOLATION  the brain runs in a separate process and never holds the key")
(println (format "  brain child can read the commission key: ~a" (equal? 'ok (car (proc-eval "(println ISLAND-KEY)" 5)))))
(println "")
(println "CLAIM (narrow): the drone provably runs the owner-signed law and cannot be")
(println "remotely made to run a rogue one or leave its proven fence. Worst case is a")
(println "proven safe-hold. Sensor integrity and mission availability are separate problems.")

(shell (string-append "rm -rf " ISLAND-BOX))
