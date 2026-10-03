#!/usr/bin/env bash
# The definition of a green tree. Run: bash .claude/skills/verify/verify.sh
#
# Verifies the tree it is run from (the main checkout or a worktree) and
# changes nothing in it. Prints one PASS/FAIL/SKIP line per check, with the tail
# of each failure and the file holding its full output, and exits 1 if any check
# failed. Only a failed deps.get or compile stops the run early, since nothing
# after them can run.
#
# There are no flags: a run that skips a check has not verified the tree.

set -uo pipefail

TAIL_LINES=40
LOG_DIR="$(mktemp -d)"
SCHEMA=mobile/schema.graphql

cd "$(git rev-parse --show-toplevel)" || exit 1

# A worktree gets its own test database, as in .claude/hooks/gates.sh.
case "$PWD" in
*/.worktrees/*)
  : "${MIX_TEST_PARTITION:=_$(basename "$PWD" | tr -c 'a-zA-Z0-9\n' '_')}"
  export MIX_TEST_PARTITION
  ;;
esac

FAILED=()

check() {
  local name="$1" log
  shift
  log="$LOG_DIR/$(printf '%s' "$name" | tr -c 'a-zA-Z0-9' '_').log"
  if "$@" >"$log" 2>&1; then
    echo "PASS  $name"
  else
    echo "FAIL  $name  (full output: $log)"
    tail -n "$TAIL_LINES" "$log" | cut -c1-200 | sed 's/^/      /'
    FAILED+=("$name")
  fi
}

finish() {
  if [ "${#FAILED[@]}" -eq 0 ]; then
    echo "GREEN"
    exit 0
  fi
  echo "RED: ${FAILED[*]/%/;}"
  exit 1
}

# Generated into a temp file and compared, so a stale schema is reported
# rather than silently rewritten.
schema_drift() {
  local fresh
  fresh="$(mktemp)"
  mix absinthe.schema.sdl --schema WerewolfAshWeb.GraphqlSchema "$fresh" >/dev/null || return 1
  diff -u "$SCHEMA" "$fresh" || {
    echo "$SCHEMA is stale: run mix graphql.codegen"
    return 1
  }
}

changed_files() {
  git diff --name-only "$(git merge-base HEAD origin/main 2>/dev/null || echo HEAD)"
  git ls-files --others --exclude-standard
}

check "mix deps.get" mix deps.get
check "mix compile --warnings-as-errors" mix compile --warnings-as-errors
[ "${#FAILED[@]}" -eq 0 ] || finish

check "mix deps.unlock --check-unused" mix deps.unlock --check-unused
check "mix hex.audit" mix hex.audit
check "mix ash.codegen --check" mix ash.codegen --check
check "mix format --check-formatted" mix format --check-formatted
check "mix credo --strict" mix credo --strict
check "graphql schema drift" schema_drift
if [ -d mobile/node_modules ]; then
  check "graphql typed documents drift" npm --prefix mobile run codegen -- --check
else
  echo "SKIP  graphql typed documents drift (mobile/node_modules not installed)"
fi
check "mix test --warnings-as-errors" mix test --warnings-as-errors
check "mix dialyzer" mix dialyzer --format short
# Not grep -q: it closes the pipe early and pipefail reports git's SIGPIPE.
if changed_files | grep '^\.claude/hooks/' >/dev/null; then
  check "hook tests" bash .claude/hooks/test-hooks.sh
else
  echo "SKIP  hook tests (nothing under .claude/hooks/ changed)"
fi

finish
