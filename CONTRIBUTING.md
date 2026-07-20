# Contributing to shouzhong

shouzhong is provably-safe control built on [Rusty](https://github.com/TheLakeMan/rusty)
— five-gate `certify-plant`, inductively-proven control over finite state
domains, gated actuators. This document covers the **legal terms** under which
contributions are accepted and the **technical standards** every change must meet.
Both exist for the same reason: shouzhong's value is a narrow, checkable claim
about safety on a bounded domain, and neither its licensing nor that claim can
rest on sand.

---

## Contributor License Agreement (CLA)

shouzhong is offered under a **dual license**: the [GNU Affero General Public
License v3 or later](./LICENSE) for the community, and a separate commercial
license for those whose use the AGPL doesn't fit (see [COMMERCIAL.md](./COMMERCIAL.md)).
That dual model only works if a single party holds the right to relicense the
**entire** codebase — so contributions require the grant below.

**By submitting a contribution** (a pull request, patch, or any other change) to
this project, you agree that:

1. **You own the rights** to the contribution, or have permission to submit it
   under these terms, and it is your original work (or you've clearly identified
   any third-party material and its license).
2. **You grant Nicholas Vermeulen** a perpetual, worldwide, non-exclusive,
   royalty-free, irrevocable license to use, reproduce, modify, distribute, and
   **relicense** your contribution, including as part of shouzhong under **both**
   the AGPL-3.0-or-later **and** any commercial license terms now or later offered.
3. **You retain copyright** to your contribution — this grant is a license, not an
   assignment. Your name stays on your work.
4. Your contribution is provided **"as is"**, without warranty of any kind.

Without this grant, a single merged change under AGPL-only terms would permanently
fragment the licensing of the file it touched.

---

## Technical standards

shouzhong's value is that its safety is *proven*, not asserted. A change that
weakens that discipline weakens the whole project:

- **Narrow claims only.** shouzhong's claim is exact: *proven safe on the declared,
  bounded domain* — never "safe" without the domain. A proof over finite state
  domains says nothing beyond them; a state outside the declared set is outside
  the claim. State the caveat, don't hide it.
- **Tests-first, real before/after.** A clean run is not evidence. Every new gate,
  plant, or actuator bound needs a golden-test row (`./run_tests.sh`), and a
  reckless controller must be *shown rejected*, not assumed. Gates after a failure
  read `not-reached`, never `passed`.
- **Built on Rusty, no new engine.** shouzhong is pure Lisp over Rusty's
  primitives (`check-exhaustive`, `certify-plant`, `defrust` proof transfer).
  Keep plants integer/exact-valued so exhaustive state coverage stays meaningful;
  don't add a dependency that isn't Rusty.
- **Match the surrounding code** — its idiom, naming, and gate ordering. Static
  gates run before anything the controller can execute.

---

## How to submit

1. Open an issue first for anything non-trivial.
2. Keep pull requests focused: one concern per PR.
3. Run `./run_tests.sh` and make sure the suite passes before submitting.
4. By opening the PR, you agree to the CLA above.

Questions about contributing or licensing: **thelakeman@protonmail.com**.

☯ *In memory of my brother.*
