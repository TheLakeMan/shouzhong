;;; island.lisp — the safety-island rehearsal: a software model of the on-robot
;;; proven gate + off-robot signing authority, for the shouzhong drone.
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; THE ARCHITECTURE (see also the design sketch). An autonomous robot can't ask
;;; a human to authorize each actuation — so the root of trust changes what it
;;; authorizes and WHERE it lives:
;;;   • authority moves from per-ACTION to per-CONTROLLER: the owner signs the
;;;     proven control law off-robot; the island runs it ONLY if the signature
;;;     verifies. A rogue/tampered law never executes.
;;;   • the "executor" becomes a small, isolated gate ON the robot, sitting on
;;;     the actuator path. The untrusted BRAIN (LLM planner, networked, assume
;;;     compromised) only PROPOSES setpoints; the island runs the SIGNED proven
;;;     law and gates every command against the proven fence. Worst a hostile
;;;     brain achieves is a rejected proposal → the drone holds. It can never
;;;     command a state outside the fence, and can never load a rogue law.
;;;
;;; This is the split rehearsed in software: the brain runs in a SEPARATE process
;;; (proc-eval — its own memory, env-scrubbed) and reaches the island only
;;; through a proposal parsed as DATA, never code. The island holds the key and
;;; the proven law; the brain holds neither.
;;;
;;; HONEST SCOPE. (1) The signature is a REAL Ed25519 asymmetric signature (Rusty
;;; ≥0.79.0): the owner signs a control-law source with a PRIVATE key; the island
;;; holds only the PUBLIC key and verifies. A compromised robot can't mint owner
;;; signatures — it never holds the secret. In THIS rehearsal the private key is
;;; generated from a fixed seed in-process so the file is self-contained and
;;; deterministic; the real owner's private key lives OFF-robot (a USB token /
;;; secure element) and only the public key ships to the robot — see the
;;; owner-side vs robot-side split below (island-sign vs island-verify). (2)
;;; proc-eval is memory/authority isolation, not a filesystem jail — the brain
;;; can do its own I/O, it just can't reach the key or the actuators. (3) This is
;;; the software logic of the safety island; the real guarantee needs the gate on
;;; a physically isolated MCU on the actuator path (secure-boot, signed firmware).
;;; Sensor integrity (spoofed state) is a separate, named problem — out of scope.

(load "shouzhong.lisp")
(load "drone3d.lisp")

(define ISLAND-BOX "/tmp/shouzhong-box")

;; ── The commissioning keypair (Ed25519) ─────────────────────────────────────
;; OWNER side vs ROBOT side is the whole point. The SEED (= private key) belongs
;; to the owner and lives OFF the robot; here it's a fixed rehearsal seed so the
;; signatures are reproducible (a real owner draws 32 bytes from OS randomness
;; once: `head -c32 /dev/urandom | xxd -p -c32`, and keeps it on a USB token).
;; The island — the on-robot code — holds ONLY OWNER-PUBLIC and never the secret.
(define OWNER-SEED "5ec0de0057a1e77e5ec0de0057a1e77e5ec0de0057a1e77e5ec0de0057a1e77e")
(define OWNER-KP (ed25519-keygen OWNER-SEED))
(define OWNER-SECRET (car OWNER-KP))    ; owner-only, off-robot in reality
(define OWNER-PUBLIC (cadr OWNER-KP))   ; the ONLY key the island holds

;; island-sign runs on the OWNER's machine at commission time (never on the robot).
(define (island-sign datum) (ed25519-sign OWNER-SECRET (format "~s" datum)))
;; island-verify runs on the ROBOT and touches only the public key. Refuse-by-
;; default: any malformed/absent signature verifies as #f (ed25519-verify never
;; raises), so a missing or forged signature can only ever DENY, never crash.
(define (island-verify datum sig) (ed25519-verify OWNER-PUBLIC (format "~s" datum) sig))

;; ── The proven fail-safe ────────────────────────────────────────────────────
;; NOT a brake: verify-axis REFUTES pure-brake at the fence (from the floor with
;; inward velocity and an adverse gust, braking still crosses). The proven
;; fail-safe is the mission law aimed at a fixed safe HOME on the mission grid —
;; a controlled "return to safe hold". Because HOME is a grid waypoint, this is
;; the SAME ∀-waypoint theorem certify-drone already proved, specialized — no new
;; proof needed. "Refuse to act" is itself a proven action.
(define HOME '(48 28 20))
(define (failsafe-controller s)
  (list (axis-control (nth s 1) (nth s 2) (car HOME)   XMAX)
        (axis-control (nth s 3) (nth s 4) (cadr HOME)  YMAX)
        (axis-control (nth s 5) (nth s 6) (caddr HOME) ZMAX)))

;; the negative control the golden pins: naive per-axis brake, refuted by the
;; checker (proof it is NOT a safe fail-safe).
(define (brake-axis p v tgt limit) (clamp (- 0 v) (- 0 AMAX) AMAX))

;; ── island-load: an IN-FLIGHT controller runs ONLY if its signature verifies ──
;; (signed <fn>) for a valid signed law; (refused-unsigned <failsafe>) otherwise.
;; A tampered/rogue source is NEVER eval'd — the island falls back to the proven
;; fail-safe LOITER (not motors-off: this path is for an airborne drone, where
;; cutting the motors is a crash, not a safe-hold). The boot gate below is the
;; other half — on the ground, no valid signature means the motors never arm.
(define (island-load datum sig)
  (if (island-verify datum sig)
      (list 'signed (eval datum))
      (list 'refused-unsigned failsafe-controller)))

;; ── The boot gate: won't start without the owner key ─────────────────────────
;; On power-up the robot ARMS its actuators ONLY if a valid owner signature over
;; the mission law is present. No valid signature — stolen robot, wiped key,
;; forged law — → 'inert: the motors never spin, the machine sits. This is the
;; anti-theft / anti-hijack property the whole split exists for: a compromised or
;; stolen autonomous machine with no owner key does NOTHING at all. On the ground
;; "do nothing" is the safe state (unlike in flight — see island-load).
(define (island-arm datum sig)
  (if (island-verify datum sig) 'armed 'inert))

;; Full sequence: BOOT, then (only if armed) FLY. An inert machine never enters a
;; flight — zero ticks, zero actuation. Returns (armed <flight>) or (inert
;; no-actuation), where <flight> is an island-run result.
(define (island-mission datum sig state0 brain-src ticks)
  (if (equal? (island-arm datum sig) 'armed)
      (list 'armed (island-run (island-load datum sig) state0 brain-src ticks))
      (list 'inert 'no-actuation)))

;; The mission controller as a SIGNED artifact: source data + its commissioned
;; signature. Follows the installed waypoint (state slots 7/8/9).
(define MISSION-SOURCE
  '(lambda (s)
     (list (axis-control (nth s 1) (nth s 2) (nth s 7) XMAX)
           (axis-control (nth s 3) (nth s 4) (nth s 8) YMAX)
           (axis-control (nth s 5) (nth s 6) (nth s 9) ZMAX))))
(define MISSION-SIG (island-sign MISSION-SOURCE))

;; ── The untrusted brain, isolated in a child process ────────────────────────
;; Parse the child's one-line proposal "x y z" as DATA (never eval). First line
;; only, so a trailing newline can't break it; non-numeric → 'no-proposal.
(define (parse-proposal text)
  (let ((toks (string-split (car (string-split text "\n")) " ")))
    (if (= (length toks) 3)
        (let ((xs (map string->number toks)))
          (if (all? number? xs) xs 'no-proposal))
        'no-proposal)))

;; Run brain-src in a fresh child with only STATE injected — never the key. Its
;; sole channel back is the printed proposal. A crash/timeout/garbage → the
;; island simply gets no proposal and holds.
(define (brain-propose brain-src state)
  (let ((r (proc-eval
             (string-append "(define STATE '" (format "~s" state) ") " brain-src)
             10)))
    (if (equal? (car r) 'ok) (parse-proposal (cadr r)) 'no-proposal)))

;; ── One island tick ─────────────────────────────────────────────────────────
;; brain proposes → island gates the waypoint → runs the ACTIVE (signed) law →
;; gates the actuation → steps the world. Returns (next-state record).
(define (in-fence? s)
  (and (axis-safe? (nth s 1) (nth s 2) XMAX)
       (axis-safe? (nth s 3) (nth s 4) YMAX)
       (axis-safe? (nth s 5) (nth s 6) ZMAX)))

(define (island-tick active s brain-src)
  (let* ((proposal (brain-propose brain-src s))
         (gate (if (list? proposal) (gated-actuate set-waypoint! proposal)
                   (list 'rejected 'no-proposal)))
         (admitted (equal? (car gate) 'ok))
         (s1 (if admitted (install-waypoint s proposal) s))
         (accel (active s1))
         (motor (gated-actuate motor3! accel))
         (next (world-step s1 accel)))
    (list next
          (list 'proposal proposal
                'admitted admitted
                'accel accel
                'motor-ok (equal? (car motor) 'ok)
                'in-fence (in-fence? next)))))

;; ── The island run ──────────────────────────────────────────────────────────
;; load = (island-load ...). Loops `ticks` times against the untrusted brain.
;; Returns (status final-state log) where status is 'signed / 'refused-unsigned.
(define (island-run load state0 brain-src ticks)
  (let ((status (car load)) (active (cadr load)))
    (let loop ((s state0) (k ticks) (log '()))
      (if (= k 0)
          (list status s (reverse log))
          (let ((step (island-tick active s brain-src)))
            (loop (car step) (- k 1) (cons (cadr step) log)))))))

;; every tick stayed in the fence?
(define (run-all-in-fence? result)
  (all? (lambda (rec) (equal? (nth rec 9) #t)) (caddr result)))
