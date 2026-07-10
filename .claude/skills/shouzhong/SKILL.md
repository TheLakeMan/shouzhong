---
name: shouzhong
description: Work on shouzhong (this repo) — the provably-safe control-loop library on Rusty. Covers the five-gate architecture, test discipline, and gotchas. Use for any change to shouzhong.lisp, thermostat.lisp, or the tests.
---

# Working on shouzhong

守中 "hold to the center" — provably-safe control loops on Rusty. Pure Lisp,
zero new interpreter code. Flagship #1 of the "guaranteed agentic AI" line;
sibling of wuwei (`/wuwei`, agent-tool gating — shared certification pattern).
**Currently local-only by owner instruction (2026-07-10): do not create a
GitHub repo or push without being asked.**

## Layout & architecture

- `shouzhong.lisp` — the kernel. Five gates in `certify-plant`, strictly
  ordered static→dynamic (wuwei's 2.1 discipline): (1) controller purity via
  `check-effects`, (2) registry certification (`certify-tool-chain` + effect
  budget), (3) `verify-actuation` (exhaustive, over ALL domain states),
  (4) base case `safe?(state0)`, (5) `verify-controller` (inductive step).
  **Don't reorder the gates** — static checks must reject before anything
  executes. `run-gated` still routes every tick through `safe-call`
  (defense in depth); `certified-loop` = certify then run.
  `verify-native-equiv` transfers proofs to `defrust`-compiled laws by
  exhaustive equality over the same domains.
  The MISSION LAYER (`run-gated-until`, `run-mission`) composes an unproven
  planner over a proven controller at the SETPOINT: make the setpoint a
  domain dimension in `verify-controller`, give the setpoint tool the same
  predicate as its precondition, and every admissible proposal is
  pre-proven. Don't let those two predicates drift apart.
- `thermostat.lisp` / `corridor.lisp` — reference plants (heater; corridor
  robot with setpoint-quantified proofs, 2205 states). Integer-only worlds
  (exact arithmetic is what makes exhaustive coverage a proof — keep it
  that way). Bound predicates (`power-ok?`, `accel-ok?`, `target-ok?`) are
  deliberately the single source of truth for "in bounds": the proofs AND
  the tool preconditions use the same one — don't fork them.
- `shouzhong-test.lisp` / `corridor-test.lisp` + `expected_*.txt` — golden
  tests, run via `./run_tests.sh` (needs `rusty` on PATH + rustc for the
  defrust rows). Deterministic: no LLM, no timings; bus files under
  `/tmp/shouzhong-box/` are reset in the fixtures. After changes:
  `rusty <test>.lisp > expected_<name>.txt` then rerun and diff.
- `demo-pilot.lisp` / `demo-mission.lisp` — live LLM (localhost:8080), NOT
  in the suite; both verified end-to-end against the owner's llama-server
  (slow, ~90s/call at 512 tokens — keep demo loops to ~3 LLM calls).
- `USE_CASES.md` — positioning: event drone geofencing (n-D corridor),
  HVAC, small-hardware thesis; keep claims narrow (proof is about the
  quantized model; sensing/estimation not covered).

## Gotchas

- States are lists (`'(20)`), and the verify functions receive domain points
  as arg-lists (`(lambda args ...)` — one domain per state component).
  Controllers take the state LIST; `defrust` laws take scalars — wrap them
  (`(define (controller-native s) (law-native (car s)))`).
- `check-effects` returns `'pure` or a findings list — compare with
  `equal?` against `'pure`, not `null?`.
- `check-exhaustive` failures return a list of `((args) reason)`
  counterexamples; `certify-plant` reports only the first (`car`).
- Keep controllers total over the WHOLE domain (0..40 here), not just the
  safe band — gate 3 quantifies over every state.
- Rebuild/refresh `rusty` after interpreter changes:
  `cd ~/projects/artifacts/rusty && cargo install --path . --bin rusty --root ~/.local`.

## Conventions

AGPL-3.0-or-later headers on every file; ☯ (never a crab); dedication
exactly "In memory of my brother."; never reference Taoscii. Golden-test
discipline is non-negotiable — anything nondeterministic goes in `demo-*`.
