;;; drone3d-native.lisp — the drone axis proof, compiled to native code.
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; The same per-axis inductive property as drone3d.lisp's verify-axis,
;;; restructured scalar (defrust has no lists — every value is f64,
;;; 1.0/0.0 stand in for booleans) and compiled to one .so via defrust*.
;;; check-exhaustive (Rusty ≥0.36.0) recognizes a native property and
;;; sweeps it with direct function calls, split across CPU cores — only
;;; f64s cross threads, and counterexamples come back in the same order
;;; as the interpreted sweep. Measured on the x-axis (79,992 states):
;;; interpreted 2.25 s → native parallel ~1.2 ms on this machine.
;;;
;;; TRUST STORY (same as the compiled control law): the proof of record
;;; is the interpreted one; drone3d-test.lisp checks the native property
;;; agrees with it on verdicts AND on the negative control's full
;;; counterexample list. Prove it slow once, re-check it fast at every
;;; boot.
;;;
;;; The fence limit rides along as a one-value domain (last argument), so
;;; this single compiled group serves all three axes. The constants here
;;; (VMAX 5, AMAX 2, brake table) mirror drone3d.lisp — keep them in sync.

(defrust*
  (bt-n (v)
    (let ((av (abs v)))
      (cond ((<= av 1) 0) ((<= av 2) 1) ((<= av 3) 3) ((<= av 4) 6) (else 10))))
  (stepv-n (v a w) (max -5 (min 5 (+ v a w))))
  (stepp-n (p v a w) (+ p (stepv-n v a w)))
  (safe-n (p v limit)
    (if (and (>= p 0) (<= p limit)
             (or (and (> v 0) (<= (+ p (bt-n v)) limit))
                 (and (<= v 0) (>= (- p (bt-n v)) 0))))
        1 0))
  (gust3-n (p v a limit)
    (min (safe-n (stepp-n p v a -1) (stepv-n v a -1) limit)
         (min (safe-n (stepp-n p v a 0) (stepv-n v a 0) limit)
              (safe-n (stepp-n p v a 1) (stepv-n v a 1) limit))))
  (law-n (p v tgt limit)
    (let ((amb (max -2 (min 2 (- (max -5 (min 5 (- tgt p))) v)))))
      (if (>= (gust3-n p v amb limit) 1) amb (max -2 (min 2 (- 0 v))))))
  (calm-law-n (p v tgt limit)
    (let ((amb (max -2 (min 2 (- (max -5 (min 5 (- tgt p))) v)))))
      (if (>= (safe-n (stepp-n p v amb 0) (stepv-n v amb 0) limit) 1)
          amb (max -2 (min 2 (- 0 v))))))
  ;; inductive step, 1.0 = holds: safe(p,v) implies safe(step(p,v,law,w))
  (axis-prop-n (p v tgt w limit)
    (if (>= (safe-n p v limit) 1)
        (let ((a (law-n p v tgt limit)))
          (safe-n (stepp-n p v a w) (stepv-n v a w) limit))
        1))
  ;; negative control: same law with the calm-air-only guard
  (calm-prop-n (p v tgt w limit)
    (if (>= (safe-n p v limit) 1)
        (let ((a (calm-law-n p v tgt limit)))
          (safe-n (stepp-n p v a w) (stepv-n v a w) limit))
        1)))

;; Native sweep over one axis: same domains as verify-axis, plus the
;; fence limit as a one-value domain.
(define (verify-axis-native prop limit waypoints)
  (check-exhaustive prop
    (list (range 0 (+ limit 1)) (range (- 0 VMAX) (+ VMAX 1))
          waypoints GUSTS (list limit))))

;; Interpreted counterexamples carry 4-element states; the native sweep
;; appends the limit domain value — strip it for comparisons.
(define (strip-limit cexs)
  (if (equal? cexs 'verified) 'verified
      (map (lambda (c)
             (let ((args (car c)))
               (list (list (nth args 0) (nth args 1) (nth args 2) (nth args 3))
                     (cadr c))))
           cexs)))
