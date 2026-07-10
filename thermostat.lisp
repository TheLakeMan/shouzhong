;;; thermostat.lisp — the reference shouzhong plant: an integer thermostat.
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; A room at AMBIENT 10°C loses 1°/tick whenever it is warmer than ambient;
;;; the heater adds its power level (integer 0..3) each tick. Everything is
;;; integer-valued on purpose: exact arithmetic is what makes exhaustive
;;; state coverage a proof rather than a sample.
;;;
;;;   comfort band  19..23   (what the controller aims for)
;;;   SAFETY band   15..26   (pipes freeze below, hardware overheats above —
;;;                           the invariant the proof is about)
;;;   state domain   0..40   (every temperature we quantify over; wider than
;;;                           the safe band so actuation bounds hold even
;;;                           from bad states)

(define AMBIENT 10)

(define (world-step s p)
  (let ((t (car s)))
    (list (+ t p (if (> t AMBIENT) -1 0)))))

(define (safe? s)
  (let ((t (car s)))
    (and (>= t 15) (<= t 26))))

;; Hardware contract: heater power is an integer 0..3. This one predicate is
;; used by BOTH proofs (verify-actuation) and the runtime gate (the tool
;; precondition below) — one source of truth for "in bounds".
(define (power-ok? p)
  (and (number? p) (>= p 0) (<= p 3) (= p (floor p))))

;; ── The control law, interpreted and compiled ─────────────────────────────
;; Below the band: full power (+2/tick net). In the band: power 1 exactly
;; balances the leak (hold). Above: off (-1/tick net).
(define (law t)
  (cond ((< t 19) 3)
        ((<= t 23) 1)
        (else 0)))

(define (controller s) (law (car s)))

;; The same law through defrust: real Rust, compiled by rustc, loaded as a
;; native function. verify-native-equiv (see the test) proves it equal to
;; `law` on every domain temperature, which transfers the safety proof to
;; the compiled artifact — prove it slow, run it fast.
(defrust law-native (t)
  (cond ((< t 19) 3)
        ((<= t 23) 1)
        (else 0)))

(define (controller-native s) (law-native (car s)))

;; ── The actuator: the ONLY side effect in the plant ───────────────────────
;; Simulated hardware register: each accepted command is appended to a bus
;; file, so the bus is a complete audit trail of everything that ever fired.
(define HEATER-BUS "/tmp/shouzhong-box/heater-bus.log")

(deftool heater! (p)
  "Write heater power p to the (simulated) hardware bus. Gated: safe-call checks power-ok? before this body runs."
  (begin (file-append HEATER-BUS (format "~a\n" p)) p))

;; Spec: one numeric param, one declared effect, and the SAME power-ok? the
;; proof used as the precondition. Declaring fewer effects than the body has
;; would fail certification (effect honesty); asking for more than the
;; budget allows would too.
(deftool-spec heater! '((power number)) '(file-append) power-ok? '())

(define HEATER-BUDGET '(file-append))
(define HEATER-REGISTRY (list heater!))

;; The state domain for all exhaustive checks: temperatures 0..40.
(define TEMP-DOMAIN (list (range 0 41)))
