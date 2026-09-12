#!/usr/bin/env bash
# Quality gate for bead work: compile, codegen check, lint, tests.
#
# Wired twice in .claude/settings.json:
#   PreToolUse on Bash - runs only for commands that contain "git push"
#   SubagentStop with matcher "coder" - runs when the coder tries to finish
#
# Exit 2 blocks the action and feeds the failing tail back to the agent, so a
# red tree can neither leave the branch nor be handed to the reviewer.
# Checks run cheapest first and stop at the first failure.

set -uo pipefail

TAIL_LINES=40
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="$(cat)"

# One field per line, so an empty field stays an empty field.
{
  read -r EVENT
  read -r CWD
  read -r COMMAND
} < <(printf '%s' "$INPUT" | python3 "$HERE/_payload.py" \
  hook_event_name cwd tool_input.command)

# On PreToolUse this fires for every Bash call, so bail out unless it pushes.
if [ "$EVENT" = "PreToolUse" ]; then
  case "$COMMAND" in
  *"git push"*) ;;
  *) exit 0 ;;
  esac
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${CWD:-$PWD}}"
cd "$PROJECT_DIR" 2>/dev/null || exit 0

# Nothing to gate outside the Elixir project, or where mix is not installed.
[ -f mix.exs ] || exit 0
command -v mix >/dev/null 2>&1 || exit 0

run_gate() {
  local name="$1"
  shift
  local output
  if ! output="$("$@" 2>&1)"; then
    {
      echo "GATE FAILED: $name"
      echo "The tree must be green before you push or finish. Fix this, then retry."
      echo "Last $TAIL_LINES lines:"
      printf '%s\n' "$output" | tail -n "$TAIL_LINES"
    } >&2
    exit 2
  fi
}

run_gate "mix compile --warnings-as-errors" mix compile --warnings-as-errors
run_gate "mix ash.codegen --check" mix ash.codegen --check
run_gate "mix lint" mix lint
run_gate "mix test" mix test

exit 0
