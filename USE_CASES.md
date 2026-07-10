# What shouzhong is for — and what it isn't

The kernel proves one shape of thing: **a finite-state plant, an invariant,
a controller, and a gate** — the controller provably never leaves the
invariant set (inductive, exhaustively checked), and no command outside the
hardware/zone contract ever reaches an actuator, no matter who proposed it.
Anything that fits that shape fits shouzhong.

## Geofenced drones at events (demonstrated: `drone3d.lisp`)

The corridor robot is a 1-D geofence: "never leaves cells 0..20" is proven
over every (position, velocity, setpoint), and the setpoint gate only admits
destinations inside the fence. `drone3d.lisp` is the same theorem in three
dimensions — 100 m × 60 m × 40 m zone, per-axis proofs with an adversarial
gust quantified in the domain (120,351 states), waypoint gate on a mission
grid, and a gusty mission flown in the golden test. The general shape:

- The **zone is the invariant**: quantize the permitted volume into cells;
  `safe?` = inside the zone with enough braking margin (the corridor's
  brake-travel term, per axis).
- The **planner is untrusted by construction**: the pilot seat — LLM, ground
  station, or a human with a joystick — only ever submits setpoints through
  the gate, and the gate's precondition is the same predicate the proof
  quantified over. A hostile or buggy planner cannot aim the drone outside
  the fence (the live demo shows the model *complying* with a "fly past the
  wall" demand and the gate refusing it).
- The **audit is data**: every admitted setpoint and every actuator command
  lands on the bus in order; refusals never do. "Prove what the drone was
  asked to do" is a file read.

Honest engineering notes, before anyone flies this:

- **State-space size.** `check-exhaustive` caps at 1M combinations. The
  corridor is 2205 states; a full 3-D product space would be billions. The
  honest moves — both used by `drone3d.lisp` — are coarse quantization and
  decomposing axes when dynamics decouple (a quadrotor's x/y/z largely do):
  three 1-D proofs cover a box zone at a tiny fraction of the product
  space, with the composition argument stated openly as the one paper step.
  Irregular zones need the full product or a conservative box
  under-approximation.
- **The proof is about the model.** Wind, sensor noise, and continuous
  dynamics live outside `world-step`. The claim is "safe per this quantized
  model with these margins" — the margins (brake-travel analogues) are where
  model error must be absorbed, and stating that is part of the product.
- **Timing is measured, not guaranteed** (deadline misses are counted and
  returned as data; the control law itself can be `defrust`-compiled to
  native for tick-rate headroom).

## Building/HVAC regulation (the thermostat, literally)

The reference plant already is one: invariant "never outside 15–26°C" proven
over every temperature, actuator contract enforced per command, audit on the
bus. Scale the state to (temp, occupancy, valve) tuples and the same five
gates apply. The gate story matters commercially here: an LLM "energy
optimizer" can be given the setpoint tool and *nothing else*.

## The common thread: small hardware

Everything above runs as one small binary plus plain-text Lisp — no ML
framework, no external verifier, no cloud dependency. Proofs are cheap
(exhaustive checks over finite integer domains), the hot law compiles to
native code, and the audit is a file. That is deliberate: the target is the
class of machines that ride *on* the drone, *in* the thermostat, at the edge
— where the models are headed next.

## What it is not

- Not a substitute for continuous-dynamics verification (no differential
  equations, no reachability analysis over reals — finite integer domains
  only, by design).
- Not a guarantee about sensing or estimation: the state the controller sees
  is assumed correct; verifying the estimator is its own problem.
- Not "unjailbreakable AI." The claim is narrower and checkable: no command
  outside the proven contract reaches an actuator, and refusals are data.
