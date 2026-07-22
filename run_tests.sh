#!/usr/bin/env bash
# shouzhong test runner — golden-file comparison, mirroring Rusty's approach.
# Requires the `rusty` interpreter on PATH (override with RUSTY=/path/to/rusty)
# and rustc (the proof-transfer rows compile the control law with defrust).
set -euo pipefail
cd "$(dirname "$0")"
RUSTY="${RUSTY:-rusty}"

command -v "$RUSTY" >/dev/null 2>&1 || {
  echo "error: '$RUSTY' not found. Install Rusty and put it on PATH, or set RUSTY=/path/to/rusty."
  echo "       Rusty: https://github.com/TheLakeMan/rusty"
  exit 1
}

fail=0
run_test() {  # file expected label
  if "$RUSTY" "$1" 2>&1 | diff - "$2" > /dev/null; then
    echo "✅  $3"
  else
    echo "❌  $3"
    "$RUSTY" "$1" 2>&1 | diff - "$2" | head -30
    fail=1
  fi
}

echo "Testing shouzhong against $("$RUSTY" --version 2>/dev/null || echo "$RUSTY")"
run_test shouzhong-test.lisp expected_shouzhong.txt "shouzhong-test.lisp (five gates + proof transfer — deterministic, no LLM)"
run_test corridor-test.lisp  expected_corridor.txt  "corridor-test.lisp (mission layer — planner over proven controller)"
run_test drone3d-test.lisp   expected_drone3d.txt   "drone3d-test.lisp (3-D drone — per-axis proofs, gusts in the domain)"
run_test island-test.lisp    expected_island.txt    "island-test.lisp (safety-island: Ed25519-signed law + boot gate + isolated brain — needs Rusty ≥0.79.0)"

# ── Package check: shouzhong is a valid, cwd-independent Rusty package ─────────
# Copies shouzhong into a throwaway $HOME/.rusty/packages/shouzhong (where pkg
# would put it) and runs the probe from an UNRELATED cwd — proving the manifest
# is well-formed and the package entry (shouzhong-pkg.lisp) loads the certify
# framework despite Rusty's cwd-relative `load`. No pkg.lisp, LLM, or network.
pkg_entry_check() {
  local label="package — manifest valid + entry loads from a foreign cwd"
  local repo; repo="$(pwd)"
  local th; th="$(mktemp -d "${TMPDIR:-/tmp}/shouzhong-pkg-XXXXXX")"
  case "$th" in /tmp/*|"${TMPDIR%/}"/*) ;; *) echo "❌  $label (unsafe tmp: $th)"; fail=1; return;; esac
  local dest="$th/.rusty/packages/shouzhong"
  mkdir -p "$dest"
  cp package.lisp shouzhong-pkg.lisp shouzhong.lisp "$dest/"

  local out; out="$(cd "$th" && HOME="$th" "$RUSTY" "$repo/shouzhong-pkg-probe.lisp" 2>&1)" || true

  local ok=1
  printf '%s\n' "$out" | grep -q '^MANIFEST-OK$'         || { echo "   manifest not well-formed"; ok=0; }
  printf '%s\n' "$out" | grep -q '^PKG-ENTRY-OK$'        || { echo "   package entry did not load the framework"; ok=0; }
  printf '%s\n' "$out" | grep -q '^SELFCHECK-GUARDED-OK$' || { echo "   shouzhong-self-check did not degrade without pkg.lisp"; ok=0; }

  rm -rf "$th"
  if [ "$ok" -eq 1 ]; then echo "✅  $label"; else echo "❌  $label"; fail=1; fi
}
pkg_entry_check

if [ "$fail" -eq 0 ]; then
  echo "🎉 ALL PASSED"
else
  echo "SOME FAILED"; exit 1
fi
