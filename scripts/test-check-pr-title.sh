#!/usr/bin/env bash
# Tests for check-pr-title.sh. Run: ./scripts/test-check-pr-title.sh
set -euo pipefail
cd "$(dirname "$0")"

failures=0

expect() {
  local want="$1" title="$2" number="$3" got=pass
  ./check-pr-title.sh "$title" "$number" >/dev/null 2>&1 || got=fail
  if [[ "$got" != "$want" ]]; then
    echo "FAIL: expected $want for \"$title\" (#$number), got $got"
    failures=$((failures + 1))
  fi
}

expect pass "feat: add a Plan editor" 12
expect fail "Add a Plan editor" 12
expect fail "feature: add a Plan editor" 12
expect pass "chore(release): v0.1.0" 18
expect pass "feat!: detect the Focus directly" 15
expect pass "fix(core)!: drop the legacy store format" 40
expect fail "feat:add a Plan editor" 12
expect fail "feat: " 12
expect fail "feat(): add a Plan editor" 12

# The squash-merge subject on main is "<title> (#N)", and it must stay within 72 chars.
# 66-char title + " (#36)" = 72.
expect pass "feat: let a Planned Cycle skip its next Break if the user says so!" 36
# 67-char title + " (#36)" = 73.
expect fail "feat: let a Planned Cycle skip its next Break when the user says so" 36
# Same 66-char title, but a 4-digit PR number pushes the subject to 74.
expect fail "feat: let a Planned Cycle skip its next Break if the user says so!" 1234
# 66 chars but 72 bytes: the limit counts characters, not bytes.
expect pass "docs: say that subjects stay ≤ 72 chars ≤ GitHub's cut ≤ UI's cuts" 36

if [[ $failures -gt 0 ]]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "All PR title tests passed"
