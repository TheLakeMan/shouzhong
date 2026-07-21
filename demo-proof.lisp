;;; demo-proof.lisp — the 15-second proof-and-gate demo (offline, no LLM).
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; The whole shouzhong claim in six lines of output: the corridor controller
;;; is proven safe over EVERY state in the declared domain, a reckless one is
;;; refused with the exact counterexample state, and the actuator gate rejects
;;; any command past the wall. This is the script behind the README GIF.
;;;
;;;   rusty demo-proof.lisp

(load "shouzhong.lisp")
(load "corridor.lisp")

(define (charge-controller s) 1)   ; full throttle, no brake guard — unsafe

(println "shouzhong — prove the controller safe on EVERY state, then gate every command.")
(println "")
(println (format "PROVE  safe controller,     2205 states => ~s"
  (certify-plant world-step controller safe? '(0 0 0) CORRIDOR-DOMAIN
                 accel-ok? CORRIDOR-REGISTRY CORRIDOR-BUDGET)))
(println (format "PROVE  reckless controller              => ~s"
  (certify-plant world-step charge-controller safe? '(0 0 0) CORRIDOR-DOMAIN
                 accel-ok? CORRIDOR-REGISTRY CORRIDOR-BUDGET)))
(println "")
(println (format "GATE   dock at 7                        => ~s" (gated-actuate set-target! 7)))
(println (format "GATE   past the wall, 25                => ~s" (gated-actuate set-target! 25)))
(println (format "GATE   behind the wall, -3             => ~s" (gated-actuate set-target! -3)))
