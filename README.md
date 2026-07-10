# ☯ shouzhong

**守中 — "hold to the center." Provably-safe control loops: the controller is
proven safe on every state before it runs, and every actuator command is
contract-checked before it fires.**

Built on [Rusty](https://github.com/TheLakeMan/rusty), a zero-dependency Lisp
interpreter in Rust. shouzhong is pure Lisp on Rusty's built-in checkers — no
new interpreter code, no external verifier, nothing to install but `rusty`
(and `rustc`, which you already have if you built Rusty).

## The claim, precisely

A shouzhong plant will not tick until **five gates** pass, in order, static
before dynamic:

1. **Controller purity** *(static)* — `check-effects` proves the control law
   is a pure function `state → action`. The actuator tool is the only path to
   a side effect; nothing hides one inside the law.
2. **Registry certification** *(static)* — every actuator tool has a typed
   spec, is **effect-honest** (its body contains no effect it doesn't
   declare), and fits the caller's effect budget. A tool that lies about its
   effects is refused before anything executes.
3. **Actuation bounds** *(exhaustive)* — from **every** state in the domain,
   safe or not, the commanded action satisfies the hardware contract.
4. **Base case** — the initial state satisfies the safety invariant.
5. **Inductive step** *(exhaustive)* — for every state in the domain,
   `safe(s) ⇒ safe(step(s, control(s)))`.

Gates 4+5 give, by induction, *the plant never leaves the safe set* — over
the stated **finite, integer-valued** state space. That scoping is the whole
honesty of the thing: "proved" means *checked on every domain point*
(Rusty's `check-exhaustive`), never an unbounded claim. Exact arithmetic is
what makes exhaustive coverage a proof rather than a sample.

Pass all five and the loop *still* routes every command through the same
per-call contract gate (`safe-call`) at runtime — so an out-of-bounds command
is rejected before the tool body runs **no matter who proposed it**: the
controller, an LLM planner, or a human with a bad idea.

### Proof transfer to compiled code

The control law can be compiled to real native code with Rusty's `defrust`
(rustc-backed JIT). `verify-native-equiv` then proves the compiled law equal
to the interpreted one **on every domain point**, which carries the safety
proof across: *prove it slow, run it fast.* The golden test does exactly this
and runs the certified loop on the native law.

## Quickstart

```bash
# 1. Install Rusty (https://github.com/TheLakeMan/rusty)
cargo install --git https://github.com/TheLakeMan/rusty --bin rusty --root ~/.local

# 2. Run the proof suite — deterministic, no LLM
./run_tests.sh
```

The reference plant is an integer thermostat (`thermostat.lisp`): room leaks
1°C/tick above ambient, heater adds its power (0–3), safety invariant
15–26°C, domain 0–40°C. The golden test proves the shipped law safe, shows a
full-blast controller **refused with counterexample** (temp 25 → 27,
overheat), an over-limit controller refused at the actuation gate, an
effect-dishonest actuator refused at certification, and the runtime gate
rejecting `9`, `1.5`, and `"hot"`:

```
09 full-blast controller refused          => (refused inductive-step ((25) "false"))
15 past hardware limit: 9                 => (rejected "safe-call: heater!: precondition violated")
18 cold start 15, 6 ticks                => (final (19) ticks 6 trajectory ((15) (17) (19) (19) (19) (19) (19)))
```

Every accepted command lands on a bus file — the audit trail of everything
that ever actuated. Refusals leave it untouched.

## The LLM pilot demo

`demo-pilot.lisp` (live LLM, not in the test suite) puts an **unproven**
planner in front of the gate: the model proposes raw heater powers; each
proposal is contract-checked before the heater fires, and a hostile
"set power 9" demand comes back as a refusal, as data:

```
tick 0: temp 20°C — LLM proposes 0 -> (ok 0)
gate verdict on the raw demand 9: (rejected "safe-call: heater!: precondition violated")
```

Honest scope: the gate enforces the *actuator contract*; it does not make a
dumb-but-in-bounds plan safe. The safety *invariant* belongs to the proven
controller. The production shape is both — which is the mission layer below.

## The mission layer: an unproven planner over a proven controller

`corridor.lisp` is a 1-D corridor robot (cells 0..20, velocity −2..2) whose
**setpoint is a dimension of the proof domain**: the inductive step is checked
over every `(position, velocity, target)` — 2205 states — so *any* setpoint
the gate admits is one the proof already covered. The planner (LLM, script,
human) gets exactly one grip on the robot, `set-target!`, and its
precondition is the same predicate the proof quantified over. The planner can
be wrong, verbose, or hostile; the worst it achieves is a boring destination.

`corridor-test.lisp` proves it deterministically (scripted planner);
`demo-mission.lisp` is the same path with a live LLM flying it. A real
transcript from the demo — the model *complied* with a hostile demand and the
gate refused it:

```
LLM proposes cell 7 -> (ok 7)
  (goal-reached (7 0 7) ticks 8)
── hostile turn ────────────────────────────────────────────────
LLM proposes cell 25 -> (rejected "safe-call: set-target!: precondition violated")
```

The corridor is a 1-D geofence — and `drone3d.lisp` is the n-dimensional
version, demonstrated.

## The drone: three axes, gusts inside the proof

`drone3d.lisp` scales the corridor to a drone over a 100 m × 60 m event zone
with a 40 m altitude band (1 m cells, 0.5 s ticks, ±10 m/s, ±4 m/s² of
authority). Two things make it more than "the corridor, three times":

- **The gust is a dimension of the proof domain**, not a margin note. The
  per-axis inductive step is checked over (position × velocity × waypoint ×
  gust) — 120,351 states across the three axes — so the invariant holds
  against a ±2 m/s² *adversarial* disturbance on every axis, every tick. The
  worst-case brake-travel term (10 m from full speed against the worst gust)
  is the explicit fence inset where model error lives.
- **The decomposition is stated, not smuggled**: near-hover x/y/z dynamics
  decouple, the zone is a conjunction of per-axis fences, so three 1-D
  proofs give the 3-D theorem — that composition is the one paper step in
  the chain; everything else is exhaustively checked.

The negative control earns its keep: the same law with a guard that only
considers *calm air* looks plausible — and the checker finds the gust that
breaks it, as a concrete counterexample:

```
03 certify-drone, end to end              => certified
04 calm-air-only guard refused            => ((7 -4 4 -1) "false")
06 beyond the fence (120 28 20)           => (rejected "safe-call: set-waypoint!: precondition violated")
```

The mission in `drone3d-test.lisp` flies three legs through a fixed gust
pattern (covered by theorem, not luck — the proofs quantified over all
gusts), with out-of-zone and off-grid waypoints rejected mid-mission and a
complete bus audit of the 65 commands that fired. See `USE_CASES.md` for the
honest engineering notes on scaling this to a real airframe.

## Files

| file | what |
|---|---|
| `shouzhong.lisp` | the kernel: five-gate `certify-plant`, `run-gated`, `certified-loop`, the mission layer (`run-gated-until`, `run-mission`), verification + gate primitives |
| `thermostat.lisp` | reference plant #1: world, invariant, law (interpreted + `defrust`-compiled), gated actuator |
| `corridor.lisp` | reference plant #2: corridor robot with the setpoint in the proof domain — the planner/controller composition point |
| `shouzhong-test.lisp` | deterministic golden test — the five gates + proof transfer |
| `corridor-test.lisp` | deterministic golden test — the mission layer, scripted planner |
| `drone3d.lisp` | reference plant #3: 3-D drone over an event zone — per-axis proofs with gusts in the domain |
| `drone3d-test.lisp` | deterministic golden test — 120,351-state certification + gusty geofenced mission |
| `demo-pilot.lisp` | live LLM proposing raw powers vs. the gate (llama-server endpoint) |
| `demo-mission.lisp` | live LLM flying the corridor robot by setpoint only |
| `USE_CASES.md` | what this is for (event drone geofencing, HVAC) and what it isn't |

## Bring your own plant

Everything is a plain value: `world-step` and the controller are pure
functions, the invariant and hardware contract are predicates, domains are
lists, the actuator is a spec'd tool. `certified-loop` composes the rest.
See `thermostat.lisp` for the shape; `robot.lisp` in the Rusty repo proves a
corridor robot with the same kernel.

## Kinship

shouzhong is the control-loop sibling of
[wuwei](https://github.com/TheLakeMan/wuwei) (無為) — same refuse-by-default
discipline, same checkers: wuwei gates an *agent's tools*; shouzhong gates a
*plant's actuators* and adds the inductive safety proof over the state space.

## License

AGPL-3.0-or-later. Copyright (c) 2026 Nicholas Vermeulen.
Commercial licensing available on inquiry.

*In memory of my brother.*
