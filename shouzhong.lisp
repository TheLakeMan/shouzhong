;;; shouzhong.lisp — provably-safe control loops for Rusty.
;;; Copyright (c) 2026 Nicholas Vermeulen
;;; SPDX-License-Identifier: AGPL-3.0-or-later
;;;
;;; 守中 — "hold to the center" (Tao Te Ching, ch. 5). A shouzhong plant will
;;; not run until its controller is proven safe, and even then every actuator
;;; command passes a contract gate before it fires. Pure Lisp on Rusty's
;;; existing checkers — no new interpreter code.
;;;
;;; FIVE GATES, IN ORDER (static before anything executes, wuwei-style):
;;;
;;;   (1) CONTROLLER PURITY (static)  — check-effects on the controller body:
;;;       the controller must be a pure function state -> action. The actuator
;;;       tool is the ONLY path to a side effect, so nothing can sneak past
;;;       the proofs inside the control law itself.
;;;   (2) REGISTRY CERTIFICATION (static) — every actuator tool has a spec,
;;;       is EFFECT-HONEST (check-effects finds nothing beyond what it
;;;       declares), and its declared effects fit the caller's effect budget.
;;;   (3) ACTUATION BOUNDS (exhaustive) — from EVERY state in the domains
;;;       (safe or not), the controller's command satisfies action-ok?.
;;;   (4) BASE CASE — the initial state satisfies the safety invariant.
;;;   (5) INDUCTIVE STEP (exhaustive) — for every state in the domains:
;;;       safe?(s) implies safe?(step(s, control(s))).
;;;
;;;   (4) + (5) give, by induction: the plant NEVER leaves the safe set —
;;;   over the stated finite state space, per Rusty's bounded-verification
;;;   rule ("proved" = checked on every domain point, never an unbounded
;;;   claim). Everything must be exact (integer-valued) arithmetic, or
;;;   exhaustive coverage of the domain means nothing.
;;;
;;; Fail any gate and certify-plant returns (refused <gate> <detail>) —
;;; no tick runs, no actuator fires. Pass all five and run-gated still
;;; routes every command through safe-call at runtime (defense in depth:
;;; the gate is cheap, and belts do not argue with braces).
;;;
;;; The verification kernel is the same shape as robot.lisp in the Rusty
;;; repo (same author, same license); vendored here because apps are
;;; separate repos and only std.lisp travels with the interpreter.

;; ── Verification kernel (exhaustive, over finite integer domains) ─────────

;; The inductive step of the safety proof. States are arg-lists: a domain
;; list per state component, and the property receives one component per
;; argument, re-packed as the state s.
(define (verify-controller world-step controller safe? domains)
  (check-exhaustive
    (lambda args
      (let ((s args))
        (implies (safe? s)
                 (safe? (world-step s (controller s))))))
    domains))

;; Actuator-bound check: the controller never commands outside its limits,
;; for ANY state in the domains (not just safe ones — a controller must not
;; saturate actuators even from bad states).
(define (verify-actuation controller action-ok? domains)
  (check-exhaustive
    (lambda args (action-ok? (controller args)))
    domains))

;; Proof transfer to a compiled artifact: a defrust-compiled law is a
;; different object from the interpreted one the proofs ran on. Exhaustive
;; equality over the same domains carries the proof across — after this,
;; verifying either controller verifies both.
(define (verify-native-equiv native reference domains)
  (check-exhaustive
    (lambda args (eq (apply native args) (apply reference args)))
    domains))

;; ── The actuator gate (wuwei's certification, plant-sized) ────────────────

;; Effects a tool declares beyond the caller's budget ('no-spec if specless).
(define (over-budget tool budget)
  (let ((s (tool-spec (tool-name tool))))
    (if (not s) 'no-spec
        (filter (lambda (e) (not (member e budget))) (spec-effects s)))))

;; Returns 'certified, or (refused <why> <detail>). Nothing runs on refusal.
(define (certify-registry tools budget)
  (let ((chain (certify-tool-chain tools)))       ; spec + effect-honesty + deps
    (if (not (equal? chain 'certified))
        (list 'refused 'chain-not-certified chain)
        (let ((over (filter (lambda (t)
                              (let ((o (over-budget t budget)))
                                (and (list? o) (not (null? o)))))
                            tools)))
          (if (null? over) 'certified
              (list 'refused 'effect-budget-exceeded
                    (map (lambda (t) (list (tool-name t) (over-budget t budget))) over)))))))

;; Per-command gate: the tool body runs ONLY if safe-call's contract
;; (arity + arg types + precondition) passes; any raise is caught and
;; returned as data. This is where an out-of-bounds command dies —
;; whether it came from a controller, an LLM, or a human.
(define (gated-actuate tool . args)
  (try-catch (list 'ok (apply safe-call (cons tool args)))
             (e) (list 'rejected e)))

;; ── The certified plant ────────────────────────────────────────────────────

;; All five gates, in order. 'certified, or (refused <gate> <detail>) with
;; nothing executed beyond the proofs themselves (the controller runs only
;; inside check-exhaustive, and it was just proven pure).
;; ── Proof as data ────────────────────────────────────────────────────────
;; certify-plant answers yes or no. certify-report answers the same question and
;; hands back the PROOF: which gates ran, what each found, how many states the
;; exhaustive gates actually covered, and the counterexample if one fell out.
;; Plain data — save-model round-trips it, mingjian can carry it, report->kg!
;; makes it queryable. A proof run yields an artifact, not just console output.
;;
;; THE GATE ORDER IS PRESERVED, which is why gates after a failure read
;; 'not-reached and never 'passed. That is not bookkeeping etiquette: gate 1
;; proves the controller PURE, and gates 3 and 5 RUN the controller over every
;; point in the domain. Filling in an impure controller's inductive-step cell
;; would mean executing its side effects thousands of times to complete a table.
;; A gate we never reached is not a gate that passed — say so, don't guess.
;;
;; domain-size is the bounded claim made countable: "proved on N states" is the
;; whole promise, stated as a number you can check against your own domains.

(define *plant-gates* '(purity registry actuation base-case inductive))

(define (domain-size domains)
  (foldl (lambda (d acc) (* acc (length d))) 1 domains))

(define (plant-report verdict refused-at n gates)
  (list 'verdict verdict 'refused-at refused-at 'domain-size n
        'gates (append gates
                       (map (lambda (g) (list g 'not-reached))
                            (list-tail *plant-gates* (length gates))))))

(define (report-verdict r)     (nth r 1))
(define (report-refused-at r)  (nth r 3))
(define (report-domain-size r) (nth r 5))
(define (report-gates r)       (nth r 7))
(define (report-gate r name)   (assoc name (report-gates r)))
(define (gate-status g)        (if g (nth g 1) #f))
(define (gate-detail r name)
  (let ((g (report-gate r name)))
    (if (and g (> (length g) 2)) (nth g 2) #f)))

(define (certify-report world-step controller safe? state0 domains
                        action-ok? registry budget)
  (let ((n      (domain-size domains))
        (purity (check-effects controller)))
    (if (not (equal? purity 'pure))
        (plant-report 'refused 'purity n (list (list 'purity 'failed purity)))
        (let ((cert (certify-registry registry budget)))
          (if (not (equal? cert 'certified))
              (plant-report 'refused 'registry n
                            (list '(purity passed) (list 'registry 'failed cert)))
              (let ((act (verify-actuation controller action-ok? domains)))
                (if (not (equal? act 'verified))
                    (plant-report 'refused 'actuation n
                                  (list '(purity passed) '(registry passed)
                                        (list 'actuation 'failed (car act))))
                    (if (not (safe? state0))
                        (plant-report 'refused 'base-case n
                                      (list '(purity passed) '(registry passed)
                                            '(actuation passed)
                                            (list 'base-case 'failed state0)))
                        (let ((ind (verify-controller world-step controller
                                                      safe? domains)))
                          (if (not (equal? ind 'verified))
                              (plant-report 'refused 'inductive n
                                            (list '(purity passed) '(registry passed)
                                                  '(actuation passed) '(base-case passed)
                                                  (list 'inductive 'failed (car ind))))
                              (plant-report 'certified 'nothing n
                                            (map (lambda (g) (list g 'passed))
                                                 *plant-gates*))))))))))))

;; Load a report into Rusty's knowledge graph so proofs are queryable across
;; runs, exactly like mingjian does with audit rows:
;;   (plant-<name> gate-<gate> <status>) (plant-<name> verdict <v>) (... domain-size N)
(define (report->kg! name r)
  (let ((s (string->symbol (format "plant-~a" name))))
    (kg-add! s 'verdict (report-verdict r))
    (kg-add! s 'domain-size (report-domain-size r))
    (for-each (lambda (g)
                (kg-add! s (string->symbol (format "gate-~a" (nth g 0))) (nth g 1)))
              (report-gates r))
    (+ 2 (length (report-gates r)))))

;; The yes/no gate, now a reading of the report — ONE implementation of the gate
;; order, not two that can drift apart. Its verdicts are unchanged (the goldens
;; are the proof of that); a second copy of this order was the real hazard.
(define (certify-plant world-step controller safe? state0 domains
                       action-ok? registry budget)
  (let ((r (certify-report world-step controller safe? state0 domains
                           action-ok? registry budget)))
    (if (equal? (report-verdict r) 'certified)
        'certified
        (let ((g (report-refused-at r)))
          (cond ((equal? g 'purity)    (list 'refused 'controller-not-pure (gate-detail r 'purity)))
                ((equal? g 'registry)  (gate-detail r 'registry))
                ((equal? g 'actuation) (list 'refused 'actuation-bounds (gate-detail r 'actuation)))
                ((equal? g 'base-case) (list 'refused 'initial-state-unsafe (gate-detail r 'base-case)))
                (else                  (list 'refused 'inductive-step (gate-detail r 'inductive))))))))

;; The runtime loop: pure world-step + pure controller = bit-for-bit
;; reproducible trajectory; every command still crosses the gate. A
;; certified controller cannot be rejected here — if it somehow is,
;; halt loudly with the trajectory so far rather than actuate blind.
(define (run-gated world-step controller actuator state0 ticks)
  (let loop ((s state0) (n 0) (traj (list state0)))
    (if (>= n ticks)
        (list 'final s 'ticks n 'trajectory (reverse traj))
        (let* ((p (controller s))
               (v (gated-actuate actuator p)))
          (if (equal? (car v) 'ok)
              (let ((s2 (world-step s p)))
                (loop s2 (+ n 1) (cons s2 traj)))
              (list 'halted 'gate-rejected p 'at-tick n
                    'trajectory (reverse traj)))))))

;; The whole discipline in one call: prove, then (and only then) run.
(define (certified-loop world-step controller safe? state0 domains
                        action-ok? registry budget actuator ticks)
  (let ((cert (certify-plant world-step controller safe? state0 domains
                             action-ok? registry budget)))
    (if (equal? cert 'certified)
        (run-gated world-step controller actuator state0 ticks)
        cert)))

;; ── The mission layer: an unproven planner over a proven controller ───────
;;
;; The composition point between a planner (LLM, script, human) and the
;; control loop is a SETPOINT — a plain number, delivered through a gated
;; tool whose precondition admits only values the safety proof quantified
;; over (make the setpoint a domain dimension in verify-controller and the
;; proof covers every value the gate can admit). The planner can be wrong,
;; hostile, or jailbroken; the worst it can do is pick a boring destination.

;; run-gated, but toward a goal predicate instead of a tick count.
(define (run-gated-until world-step controller actuator state0 goal? max-steps)
  (let loop ((s state0) (n 0))
    (cond ((goal? s) (list 'goal-reached s 'ticks n))
          ((>= n max-steps) (list 'max-steps s 'ticks n))
          (else
            (let* ((a (controller s))
                   (v (gated-actuate actuator a)))
              (if (equal? (car v) 'ok)
                  (loop (world-step s a) (+ n 1))
                  (list 'halted 'gate-rejected a 'at-tick n)))))))

;; Drive a list of setpoint proposals, each through the setpoint gate.
;; install is a pure (state value) -> state that re-aims the controller;
;; goal? reads the installed setpoint back out of the state, so one
;; predicate serves every leg. Rejected proposals are logged and skipped —
;; the plant simply stays where the last proven-safe leg left it.
;; Returns (mission-complete <state> log ((proposal verdict detail)...)).
(define (run-mission world-step controller actuator setpoint-tool install
                     goal? state0 proposals max-steps)
  (let loop ((s state0) (ps proposals) (log '()))
    (if (null? ps)
        (list 'mission-complete s 'log (reverse log))
        (let* ((p (car ps))
               (v (gated-actuate setpoint-tool p)))
          (if (equal? (car v) 'ok)
              (let ((r (run-gated-until world-step controller actuator
                                        (install s p) goal? max-steps)))
                (loop (cadr r) (cdr ps) (cons (list p 'accepted r) log)))
              (loop s (cdr ps) (cons (list p 'rejected (cadr v)) log)))))))
