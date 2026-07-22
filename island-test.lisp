;;; island-test.lisp — golden for the safety-island rehearsal.
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; Deterministic (no LLM, no timings). Pins: the proven fail-safe (naive brake
;;; REFUTED, home-loiter VERIFIED), the Ed25519 signature gate (only the owner-
;;; signed law runs), the BOOT gate (won't start without the owner key — a forged
;;; sig or rogue law → inert, motors never arm), the untrusted brain isolated in
;;; a child (can't see the secret, its output is data not code), and that whatever
;;; the brain does the drone stays in the proven fence and only in-bounds commands
;;; reach the actuator. Needs Rusty ≥0.79.0 (ed25519) and ≥0.60.0 (proc-eval).

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
(println "── multi-key authorized set (add a token key beside the backup) ──")
;; a second identity — e.g. a hardware token — signs the SAME mission law
(define TOKEN-KP  (ed25519-keygen "1111111111111111111111111111111111111111111111111111111111111111"))
(define TOKEN-PUB (cadr TOKEN-KP))
(define TOKEN-SIG (ed25519-sign (car TOKEN-KP) (format "~s" MISSION-SOURCE)))
;; with only the backup key authorized, the token's signature is NOT accepted
(row "token sig, default set {backup}    " (island-verify-any MISSION-SOURCE TOKEN-SIG (list OWNER-PUBLIC)))
;; add the token key → EITHER identity can commission the law (recovery)
(define SET2 (list OWNER-PUBLIC TOKEN-PUB))
(row "backup sig, set {backup,token}     " (island-verify-any MISSION-SOURCE MISSION-SIG SET2))
(row "token sig,  set {backup,token}     " (island-verify-any MISSION-SOURCE TOKEN-SIG  SET2))
;; a key in NEITHER set is refused, and a forged sig is refused under any set
(define STRANGER-KP  (ed25519-keygen "2222222222222222222222222222222222222222222222222222222222222222"))
(define STRANGER-SIG (ed25519-sign (car STRANGER-KP) (format "~s" MISSION-SOURCE)))
(row "stranger sig, set {backup,token}   " (island-verify-any MISSION-SOURCE STRANGER-SIG SET2))
(row "forged sig,   set {backup,token}   " (island-verify-any MISSION-SOURCE "deadbeef"   SET2))

(println "")
(println "── the boot gate: won't start without the owner key ──")
;; a valid owner signature arms the actuators; anything else → inert (motors
;; never spin). This is the anti-theft / anti-hijack property.
(row "valid owner sig → armed            " (island-arm MISSION-SOURCE MISSION-SIG))
(row "forged sig → inert (won't start)   " (island-arm MISSION-SOURCE "deadbeef"))
(row "rogue law → inert (won't start)    " (island-arm TAMPERED MISSION-SIG))
;; an inert machine flies nothing — zero ticks, zero actuation
(define boot-inert (island-mission TAMPERED MISSION-SIG S0 "(println \"48 28 20\")" 6))
(row "inert mission actuates?            " (equal? 'armed (car boot-inert)))
(row "  inert mission yields             " boot-inert)
;; the armed mission does fly, and stays in the proven fence
(define boot-armed (island-mission MISSION-SOURCE MISSION-SIG S0 "(println \"48 28 20\")" 6))
(row "armed mission → flies              " (car boot-armed))
(row "armed mission in-fence every tick? " (run-all-in-fence? (cadr boot-armed)))

(println "")
(println "── brain isolated in a child process ──")
;; the secret never crosses into the child — a brain that reaches for it gets nothing
(row "child sees the owner secret?       " (equal? 'ok (car (proc-eval "(println OWNER-SECRET)" 5))))
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
