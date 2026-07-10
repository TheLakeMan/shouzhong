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
controller. The production shape is both: the LLM plans at the setpoint
level, the proven law does the driving.

## Files

| file | what |
|---|---|
| `shouzhong.lisp` | the kernel: five-gate `certify-plant`, `run-gated`, `certified-loop`, verification + gate primitives |
| `thermostat.lisp` | the reference plant: world, invariant, law (interpreted + `defrust`-compiled), gated actuator |
| `shouzhong-test.lisp` | deterministic golden test — the guarantee, reproduced on every run |
| `demo-pilot.lisp` | live-LLM pilot vs. the gate (needs a llama-server-compatible endpoint) |

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
