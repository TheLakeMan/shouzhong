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

if [ "$fail" -eq 0 ]; then
  echo "🎉 ALL PASSED"
else
  echo "SOME FAILED"; exit 1
fi
