;;; shouzhong-test.lisp — deterministic golden test for shouzhong.
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; NO LLM, no timing, no randomness. This file is the guarantee, reproduced
;;; on every run: nothing actuates until the controller is proven safe, and
;;; nothing out of bounds actuates ever. Requires rustc on PATH (the proof-
;;; transfer rows compile the control law with defrust), which any machine
;;; that built Rusty already has.

(load "shouzhong.lisp")
(load "thermostat.lisp")

;; ── fixture: clean bus, no leftover payloads ────────────────────────────────
(dir-create "/tmp/shouzhong-box/")
(file-write HEATER-BUS "")
(define SNEAK "/tmp/shouzhong-box/sneaky.txt")
(if (file-exists? SNEAK) (file-delete SNEAK) #f)

(define (row tag val) (println (format "~a => ~s" tag val)))

;; a controller that hides a side effect in the control law
(define (sneaky-controller s) (begin (file-write SNEAK "boo") 1))
;; a controller that is unsafe but perfectly in-bounds: full power, always
(define (blast-controller s) 3)
;; a controller that commands past the hardware limit
(define (overdrive-controller s) 9)
;; an actuator that lies about its effects (declares none, appends anyway)
(deftool vent! (p) "A vent that hides its bus write." (begin (file-append HEATER-BUS (format "vent ~a\n" p)) p))
(deftool-spec vent! '((power number)) '() power-ok? '())

(println "── GATE 1: controller purity (static — nothing has executed) ──")
(row "01 control law is effect-free            " (check-effects controller))
(row "02 sneaky controller refused             "
     (certify-plant world-step sneaky-controller safe? '(20) TEMP-DOMAIN
                    power-ok? HEATER-REGISTRY HEATER-BUDGET))
(row "03 ...and its payload never fired        " (file-exists? SNEAK))

(println "")
(println "── GATE 2: actuator registry certification (static) ──────────")
(row "04 honest heater registry                " (certify-registry HEATER-REGISTRY HEATER-BUDGET))
(row "05 effect-dishonest vent refused         " (certify-registry (list vent!) HEATER-BUDGET))

(println "")
(println "── GATES 3–5: exhaustive proofs over temps 0..40 ──────────────")
(row "06 actuation: command in 0..3, ANY state " (verify-actuation controller power-ok? TEMP-DOMAIN))
(row "07 inductive step: safe stays safe       " (verify-controller world-step controller safe? TEMP-DOMAIN))
(row "08 base case: initial state 20 is safe   " (safe? '(20)))
(row "09 full-blast controller refused         "
     (certify-plant world-step blast-controller safe? '(20) TEMP-DOMAIN
                    power-ok? HEATER-REGISTRY HEATER-BUDGET))
(row "10 overdrive refused at actuation bounds "
     (certify-plant world-step overdrive-controller safe? '(20) TEMP-DOMAIN
                    power-ok? HEATER-REGISTRY HEATER-BUDGET))

(println "")
(println "── proof transfer: the law compiled to native Rust ────────────")
(row "11 compiled law = proven law, every temp " (verify-native-equiv law-native law TEMP-DOMAIN))
(row "12 compiled controller passes induction  " (verify-controller world-step controller-native safe? TEMP-DOMAIN))

(println "")
(println "── the runtime gate: per-command, before the tool body runs ──")
(row "13 bus after all proofs above            " (file-read HEATER-BUS))
(row "14 in-bounds command 2                   " (gated-actuate heater! 2))
(row "15 past hardware limit: 9                " (gated-actuate heater! 9))
(row "16 non-integer power: 1.5                " (gated-actuate heater! 1.5))
(row "17 wrong type: \"hot\"                     " (gated-actuate heater! "hot"))

(println "")
(println "── certified runs (native law, every tick gated) ──────────────")
(file-write HEATER-BUS "")     ; reset the audit for the runs below
(row "18 cold start 15, 6 ticks               "
     (certified-loop world-step controller-native safe? '(15) TEMP-DOMAIN
                     power-ok? HEATER-REGISTRY HEATER-BUDGET heater! 6))
(row "19 hot start 26, 6 ticks                "
     (certified-loop world-step controller-native safe? '(26) TEMP-DOMAIN
                     power-ok? HEATER-REGISTRY HEATER-BUDGET heater! 6))
(row "20 bus audit: every command that fired  " (file-read HEATER-BUS))
(row "21 unproven overdrive, gated at runtime "
     (run-gated world-step overdrive-controller heater! '(30) 6))
(row "22 certified-loop refuses blast outright"
     (certified-loop world-step blast-controller safe? '(20) TEMP-DOMAIN
                     power-ok? HEATER-REGISTRY HEATER-BUDGET heater! 6))

(println "")
(println "shouzhong-test: done")
