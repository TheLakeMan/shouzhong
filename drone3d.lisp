;;; drone3d.lisp — the 3-D shouzhong plant: a drone over an event zone,
;;; proven safe per axis, for every admissible waypoint, UNDER GUSTS.
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; UNITS (every number below has one): 1 cell = 1 m, 1 tick = 0.5 s.
;;;   zone       x 0..100, y 0..60     (a 100 m × 60 m event field)
;;;   altitude   z 0..40               (z = height above the event's
;;;                                     minimum-clearance floor; 0 is the
;;;                                     lowest legal altitude, not ground)
;;;   velocity   ±5 cells/tick         (±10 m/s)
;;;   accel cmd  ±2 cells/tick²        (±4 m/s² of authority)
;;;   gust       ±1 cell/tick²         (±2 m/s² disturbance, adversarial,
;;;                                     on every axis incl. vertical)
;;;
;;; THE DECOMPOSITION. A quad in near-hover has decoupled x/y/z dynamics:
;;; world-step factors into three independent axis-steps and the zone
;;; invariant is a conjunction of per-axis fences. So three 1-D proofs give
;;; the 3-D theorem. That composition is the one PAPER step in the chain
;;; (if the step never mixes axes and the invariant is a per-axis
;;; conjunction, per-axis induction composes); everything else is checked
;;; exhaustively, per axis, over (position × velocity × waypoint × gust):
;;;   x: 101·11·24·3 = 79,992   y: 61·11·14·3 = 28,182   z: 41·11·9·3 = 12,177
;;; The gust is a DIMENSION OF THE PROOF, not a margin note: the inductive
;;; step must hold for every gust value the model admits, every tick.
;;;
;;; THE MARGIN. Braking commands decel 2 but an adverse gust eats 1, so
;;; the effective decel is 1 cell/tick² — worst-case brake travel from
;;; speed v is v(v-1)/2 (10 m from full speed). That term is the fence
;;; inset: axis-safe? demands room to stop INSIDE the zone against the
;;; worst gust. This is where model error lives, and it is explicit.

(define XMAX 100)
(define YMAX 60)
(define ZMAX 40)
(define VMAX 5)
(define AMAX 2)
(define GUSTS '(-1 0 1))

(define (clamp v lo hi) (max lo (min hi v)))

;; brake travel under adverse gust (effective decel 1): index by |v|
(define BRAKE-TRAVEL '(0 0 1 3 6 10))
(define (btravel v) (nth BRAKE-TRAVEL (abs v)))

;; one axis, one tick: commanded accel a, gust w
(define (axis-step p v a w)
  (let ((v2 (clamp (+ v a w) (- 0 VMAX) VMAX)))
    (list (+ p v2) v2)))

;; the per-axis invariant: inside the fence, with room to stop inside it
;; against the worst gust
(define (axis-safe? p v limit)
  (and (>= p 0) (<= p limit)
       (if (> v 0)
           (<= (+ p (btravel v)) limit)
           (>= (- p (btravel v)) 0))))

;; a commanded accel is admissible only if EVERY gust leaves us safe
(define (gust-safe? p v a limit)
  (and (let ((s (axis-step p v a -1))) (axis-safe? (car s) (cadr s) limit))
       (let ((s (axis-step p v a 0)))  (axis-safe? (car s) (cadr s) limit))
       (let ((s (axis-step p v a 1)))  (axis-safe? (car s) (cadr s) limit))))

;; head for the waypoint; the gust-aware brake guard wins over ambition
(define (axis-control p v tgt limit)
  (let ((ambition (clamp (- (clamp (- tgt p) (- 0 VMAX) VMAX) v)
                         (- 0 AMAX) AMAX)))
    (if (gust-safe? p v ambition limit)
        ambition
        (clamp (- 0 v) (- 0 AMAX) AMAX))))

;; the negative control: same law, but its guard only considers calm air —
;; plausible-looking, and the checker finds the gust that breaks it
(define (calm-air-control p v tgt limit)
  (let ((ambition (clamp (- (clamp (- tgt p) (- 0 VMAX) VMAX) v)
                         (- 0 AMAX) AMAX)))
    (if (let ((s (axis-step p v ambition 0)))
          (axis-safe? (car s) (cadr s) limit))
        ambition
        (clamp (- 0 v) (- 0 AMAX) AMAX))))

;; ── The per-axis proofs (gust quantified alongside the state) ─────────────
(define (verify-axis control limit waypoints)
  (check-exhaustive
    (lambda (p v tgt w)
      (implies (axis-safe? p v limit)
               (let ((s2 (axis-step p v (control p v tgt limit) w)))
                 (axis-safe? (car s2) (cadr s2) limit))))
    (list (range 0 (+ limit 1)) (range (- 0 VMAX) (+ VMAX 1)) waypoints GUSTS)))

(define (verify-axis-actuation control limit waypoints)
  (check-exhaustive
    (lambda (p v tgt) (accel-ok? (control p v tgt limit)))
    (list (range 0 (+ limit 1)) (range (- 0 VMAX) (+ VMAX 1)) waypoints)))

;; ── Hardware / zone contracts (each shared by proof AND gate) ─────────────
(define (accel-ok? a)
  (and (number? a) (>= a (- 0 AMAX)) (<= a AMAX) (= a (floor a))))

;; waypoints live on a 4 m mission grid, inset 4 m from every fence — the
;; same lists the proofs quantify over, so gate-admissible ⇒ already-proven
(define (waypoint-grid limit)
  (filter (lambda (p) (= (mod p 4) 0)) (range 4 (- limit 3))))
(define XWPTS (waypoint-grid XMAX))
(define YWPTS (waypoint-grid YMAX))
(define ZWPTS (waypoint-grid ZMAX))

(define (accel3-ok? a)
  (and (list? a) (= (length a) 3)
       (accel-ok? (car a)) (accel-ok? (cadr a)) (accel-ok? (caddr a))))
(define (waypoint3-ok? p)
  (and (list? p) (= (length p) 3)
       (member (car p) XWPTS) (member (cadr p) YWPTS) (member (caddr p) ZWPTS)))

;; ── The 3-D runtime plant ──────────────────────────────────────────────────
;; state s = (n x vx y vy z vz tx ty tz); n indexes a fixed gust pattern so
;; the mission run is bit-for-bit reproducible while still being gusty. The
;; proofs above are against ADVERSARIAL gusts, so any pattern is covered.
(define WIND-PATTERN
  '((1 0 -1) (0 -1 0) (-1 1 1) (0 0 -1) (1 1 0)
    (-1 0 1) (0 1 -1) (1 -1 0) (0 0 1) (-1 -1 -1)))

(define (world-step s a)
  (let ((n (nth s 0))
        (x (nth s 1)) (vx (nth s 2))
        (y (nth s 3)) (vy (nth s 4))
        (z (nth s 5)) (vz (nth s 6))
        (tx (nth s 7)) (ty (nth s 8)) (tz (nth s 9)))
    (let* ((w (nth WIND-PATTERN (mod n (length WIND-PATTERN))))
           (sx (axis-step x vx (car a) (car w)))
           (sy (axis-step y vy (cadr a) (cadr w)))
           (sz (axis-step z vz (caddr a) (caddr w))))
      (list (+ n 1) (car sx) (cadr sx) (car sy) (cadr sy)
            (car sz) (cadr sz) tx ty tz))))

(define (controller s)
  (list (axis-control (nth s 1) (nth s 2) (nth s 7) XMAX)
        (axis-control (nth s 3) (nth s 4) (nth s 8) YMAX)
        (axis-control (nth s 5) (nth s 6) (nth s 9) ZMAX)))

;; "arrived" under gusts = station-keeping within a cell at ≤1 residual
;; speed on every axis — exact parking is a calm-air concept
(define (arrived? s)
  (and (<= (abs (- (nth s 1) (nth s 7))) 1) (<= (abs (nth s 2)) 1)
       (<= (abs (- (nth s 3) (nth s 8))) 1) (<= (abs (nth s 4)) 1)
       (<= (abs (- (nth s 5) (nth s 9))) 1) (<= (abs (nth s 6)) 1)))

(define (install-waypoint s p)
  (list (nth s 0) (nth s 1) (nth s 2) (nth s 3) (nth s 4)
        (nth s 5) (nth s 6) (car p) (cadr p) (caddr p)))

;; ── Actuators: the only side effects in the plant ─────────────────────────
(define DRONE-BUS "/tmp/shouzhong-box/drone-bus.log")

(deftool motor3! (a)
  "Command (ax ay az) acceleration on the drive motors (simulated bus write). Gated: safe-call checks accel3-ok? first."
  (begin (file-append DRONE-BUS (format "~a\n" a)) a))
(deftool-spec motor3! '((accel list)) '(file-append) accel3-ok? '())

(deftool set-waypoint! (p)
  "Admit waypoint (x y z) for the next leg (audited on the bus). Gated: only mission-grid points the per-axis proofs quantified over get through."
  (begin (file-append DRONE-BUS (format "waypoint ~a\n" p)) p))
(deftool-spec set-waypoint! '((waypoint list)) '(file-append) waypoint3-ok? '())

(define DRONE-BUDGET '(file-append))
(define DRONE-REGISTRY (list motor3! set-waypoint!))

;; ── All gates for the 3-D plant, in the kernel's order ─────────────────────
;; certify-plant's generic wrappers don't know about the gust dimension, so
;; the drone runs the same five-gate sequence with its per-axis proofs.
(define (certify-drone state0)
  (let ((purity (check-effects controller)))
    (if (not (equal? purity 'pure))
        (list 'refused 'controller-not-pure purity)
        (let ((cert (certify-registry DRONE-REGISTRY DRONE-BUDGET)))
          (if (not (equal? cert 'certified))
              cert
              (let ((ax (verify-axis-actuation axis-control XMAX XWPTS))
                    (ay (verify-axis-actuation axis-control YMAX YWPTS))
                    (az (verify-axis-actuation axis-control ZMAX ZWPTS)))
                (if (not (and (equal? ax 'verified) (equal? ay 'verified)
                              (equal? az 'verified)))
                    (list 'refused 'actuation-bounds (list ax ay az))
                    (if (not (and (axis-safe? (nth state0 1) (nth state0 2) XMAX)
                                  (axis-safe? (nth state0 3) (nth state0 4) YMAX)
                                  (axis-safe? (nth state0 5) (nth state0 6) ZMAX)))
                        (list 'refused 'initial-state-unsafe state0)
                        (let ((ix (verify-axis axis-control XMAX XWPTS))
                              (iy (verify-axis axis-control YMAX YWPTS))
                              (iz (verify-axis axis-control ZMAX ZWPTS)))
                          (if (not (and (equal? ix 'verified) (equal? iy 'verified)
                                        (equal? iz 'verified)))
                              (list 'refused 'inductive-step (list ix iy iz))
                              'certified))))))))))
