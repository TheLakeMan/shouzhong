;;; corridor.lisp — the mobile shouzhong plant: a corridor robot whose
;;; safety proof covers EVERY setpoint its planner gate can admit.
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; A 1-D robot in a corridor of cells 0..20 (walls outside), velocity
;;; -2..2, action = acceleration in {-1,0,1} — the same world robot.lisp
;;; proves in the Rusty repo, with one upgrade: the TARGET is part of the
;;; state and a dimension of the proof domain. verify-controller therefore
;;; proves "safe stays safe" for every (pos, vel, target) — 21×5×21 = 2205
;;; states — so ANY target the setpoint gate admits (integer 0..20) is one
;;; the proof already covered. That is what lets an unproven planner (LLM,
;;; script, human) re-aim the robot at will without touching the guarantee.
;;;
;;; All integer, on purpose: exact arithmetic is what makes exhaustive
;;; coverage a proof rather than a sample.

(define (clamp v lo hi) (max lo (min hi v)))

;; state s = (pos vel target); the world moves, the target rides along
;; (only the gated setpoint tool ever changes it, between legs).
(define (world-step s a)
  (let ((pos (car s)) (vel (cadr s)) (tgt (caddr s)))
    (let ((v2 (clamp (+ vel a) -2 2)))
      (list (+ pos v2) v2 tgt))))

;; Safety: inside the corridor AND stoppable before a wall. Braking from
;; |vel|=2 travels one more cell (vel passes through 1) — that overshoot
;; is the brake-travel term; anything less stops in place.
(define (brake-travel v) (cond ((= v 2) 1) ((= v -2) -1) (else 0)))
(define (safe? s)
  (let ((pos (car s)) (vel (cadr s)))
    (and (>= pos 0) (<= pos 20)
         (>= (+ pos (brake-travel vel)) 0)
         (<= (+ pos (brake-travel vel)) 20))))

;; Controller: head for the target; the brake guard wins over ambition.
(define (controller s)
  (let ((pos (car s)) (vel (cadr s)) (tgt (caddr s)))
    (let ((ambition (clamp (- (clamp (- tgt pos) -2 2) vel) -1 1)))
      (if (safe? (world-step s ambition))
          ambition
          (clamp (- 0 vel) -1 1)))))

;; A leg is done when the robot is parked on its current target.
(define (at-target? s)
  (and (= (car s) (caddr s)) (= (cadr s) 0)))

;; Hardware contracts — each the single source of truth for its gate AND
;; its proof (verify-actuation / the setpoint domain).
(define (accel-ok? a)  (and (number? a) (>= a -1) (<= a 1) (= a (floor a))))
(define (target-ok? p) (and (number? p) (>= p 0) (<= p 20) (= p (floor p))))

;; ── Actuators: the only side effects in the plant ─────────────────────────
;; One bus file = one complete audit trail: every acceleration that fired
;; and every setpoint that was admitted, in order. Refusals never land here.
(define MOTOR-BUS "/tmp/shouzhong-box/corridor-bus.log")

(deftool motor! (a)
  "Command acceleration a on the drive motor (simulated bus write). Gated: safe-call checks accel-ok? first."
  (begin (file-append MOTOR-BUS (format "~a\n" a)) a))
(deftool-spec motor! '((accel number)) '(file-append) accel-ok? '())

(deftool set-target! (p)
  "Admit setpoint p for the next leg (audited on the bus). Gated: safe-call checks target-ok? first — only setpoints the safety proof quantified over get through."
  (begin (file-append MOTOR-BUS (format "target ~a\n" p)) p))
(deftool-spec set-target! '((target number)) '(file-append) target-ok? '())

(define (install-target s p) (list (car s) (cadr s) p))

(define CORRIDOR-BUDGET '(file-append))
(define CORRIDOR-REGISTRY (list motor! set-target!))

;; The proof domain: every position × velocity × admissible setpoint.
(define CORRIDOR-DOMAIN
  (list (range 0 21) '(-2 -1 0 1 2) (range 0 21)))
