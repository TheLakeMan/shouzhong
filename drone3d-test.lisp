;;; drone3d-test.lisp — deterministic golden test for the 3-D drone plant:
;;; per-axis proofs with the gust in the domain, a geofenced gusty mission.
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; NO LLM, no timing, no randomness (the gusts follow a fixed pattern; the
;;; proofs quantify over ALL gusts, so the pattern is covered by theorem,
;;; not by luck). ~120k exhaustively checked states across three axes.

(load "shouzhong.lisp")
(load "drone3d.lisp")

;; ── fixture ─────────────────────────────────────────────────────────────────
(dir-create "/tmp/shouzhong-box/")
(file-write DRONE-BUS "")

(define (row tag val) (println (format "~a => ~s" tag val)))

(println "── the drone is certified: five gates, three axes, gusts in ──")
(println "──   the proof domain (x 79,992 / y 28,182 / z 12,177 states) ──")
(row "01 control law is effect-free            " (check-effects controller))
(row "02 motor+waypoint registry certified     " (certify-registry DRONE-REGISTRY DRONE-BUDGET))
(row "03 certify-drone, end to end             " (certify-drone '(0 4 0 4 0 20 0 4 4 20)))
(define CALM-CEX (verify-axis calm-air-control XMAX XWPTS))
(row "04 calm-air-only guard refused; the      " 'see-below)
(row "   checker found the gust that breaks it " (car CALM-CEX))

(println "")
(println "── the waypoint gate: the geofence, enforced as a contract ────")
(row "05 mid-field waypoint (48 28 20)         " (gated-actuate set-waypoint! '(48 28 20)))
(row "06 beyond the fence (120 28 20)          " (gated-actuate set-waypoint! '(120 28 20)))
(row "07 off the mission grid (49 28 20)       " (gated-actuate set-waypoint! '(49 28 20)))
(row "08 under the altitude floor (48 28 0)    " (gated-actuate set-waypoint! '(48 28 0)))
(row "09 2-D waypoint, no altitude (48 28)     " (gated-actuate set-waypoint! '(48 28)))

(println "")
(println "── the mission: gusty air, every proposal + accel gated ───────")
(file-write DRONE-BUS "")     ; reset the audit for the mission
(define M
  (run-mission world-step controller motor3! set-waypoint! install-waypoint
               arrived? '(0 4 0 4 0 20 0 4 4 20)
               '((40 20 24) (120 40 20) (96 56 36) (49 28 20) (4 4 4)) 200))
(println "10 mission log (proposal verdict outcome):")
(let loop ((rows (nth M 3)))
  (if (null? rows) #t
      (begin (println (format "   ~s" (car rows))) (loop (cdr rows)))))
(row "11 final state (n x vx y vy z vz tx ty tz)" (cadr M))

;; the audit: every admitted waypoint, every accel command, in order —
;; summarized as (total-commands admitted-waypoints)
(define BUS-LINES
  (filter (lambda (l) (> (string-length l) 0))
          (string-split (file-read DRONE-BUS) "\n")))
(row "12 bus audit: total commands that fired  " (length BUS-LINES))
(row "13 bus audit: waypoints admitted         "
     (filter (lambda (l) (string-starts-with? l "waypoint")) BUS-LINES))

(println "")
(println "── the proof, compiled: native property swept on all cores ────")
(load "drone3d-native.lisp")
(row "14 x-axis, native (79,992 states)        " (strip-limit (verify-axis-native axis-prop-n XMAX XWPTS)))
(row "15 y-axis, native (28,182 states)        " (strip-limit (verify-axis-native axis-prop-n YMAX YWPTS)))
(row "16 z-axis, native (12,177 states)        " (strip-limit (verify-axis-native axis-prop-n ZMAX ZWPTS)))
(row "17 negative control: native = interpreted,"
     'see-below)
(row "   full counterexample list              "
     (equal? CALM-CEX (strip-limit (verify-axis-native calm-prop-n XMAX XWPTS))))

(println "")
(println "drone3d-test: done")
