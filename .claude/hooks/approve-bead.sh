#!/usr/bin/env bash
# The approval gesture: "approve <bead-id>" fires the cloud pipeline for that
# bead, and "reject <bead-id>: <note>" sends its spec back to the spec author.
#
# Wired as UserPromptSubmit, so it runs before the model sees the message. That
# makes firing deterministic: the request is built here, with the same headers
# and the whole spec, rather than assembled by a model that might omit a step.
#
# Approval is the act of sending. Specs are never committed; the copy that goes
# out lives on in the pull request body, and the local file is deleted by
# sync-beads.sh once its PR merges.
#
# Secrets come from the environment only. In fish:
#   set -Ux ROUTINE_ID   trig_...
#   set -Ux ROUTINE_TOKEN sk-ant-...
#
# Exit 2 refuses the prompt and shows the reason. Exit 0 with JSON on stdout
# lets the prompt through and tells the model what already happened.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_BASE="${ROUTINE_API_BASE:-https://api.anthropic.com}"
BEAD_ID='[A-Za-z0-9_]+-[A-Za-z0-9]+(\.[0-9]+)*'

INPUT="$(cat)"
PROMPT="$(printf '%s' "$INPUT" | python3 "$HERE/_payload.py" prompt)"
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SPEC_DIR="$REPO_ROOT/.specs"

refuse() {
  echo "$1" >&2
  exit 2
}

context() {
  CTX="$1" python3 -c '
import json, os
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": os.environ["CTX"],
}}))'
  exit 0
}

# --- reject <bead-id>: <note> -------------------------------------------------
if printf '%s' "$PROMPT" | grep -qiE "^reject[[:space:]]+${BEAD_ID}[[:space:]]*:"; then
  id="$(printf '%s' "$PROMPT" | grep -oiE "^reject[[:space:]]+${BEAD_ID}" | awk '{print $2}')"
  note="$(printf '%s' "$PROMPT" | sed -E "s/^[Rr][Ee][Jj][Ee][Cc][Tt][[:space:]]+[^:]*:[[:space:]]*//")"
  context "The user rejected the spec for ${id}. Nothing was sent to the cloud.
Their feedback: ${note}
Hand this back to the spec-author subagent, have it revise .specs/${id}.md
accordingly, then run the spec-reviewer over the result and show the user the
revised spec. Do not fire the routine; only the user can approve."
fi

# --- approve <bead-id> --------------------------------------------------------
printf '%s' "$PROMPT" | grep -qiE "^approve[[:space:]]+${BEAD_ID}[[:space:]]*$" || exit 0

ID="$(printf '%s' "$PROMPT" | awk '{print $2}')"
SPEC="$SPEC_DIR/$ID.md"

[ -n "${ROUTINE_ID:-}" ] || refuse "ROUTINE_ID is not set, so there is nothing to fire. Set it with: set -Ux ROUTINE_ID trig_..."
[ -n "${ROUTINE_TOKEN:-}" ] || refuse "ROUTINE_TOKEN is not set. Set it with: set -Ux ROUTINE_TOKEN sk-ant-..."
[ -f "$SPEC" ] || refuse "No spec at .specs/$ID.md. Draft one with the spec-author subagent first, then approve."

# Close out anything that merged since the last session before firing more work.
SYNC="$(bash "$HERE/sync-beads.sh" 2>/dev/null)"

command -v bd >/dev/null 2>&1 || refuse "bd is not installed, so the bead state cannot be checked."
STATUS="$(bd show "$ID" 2>/dev/null | head -1)"
[ -n "$STATUS" ] || refuse "No bead matches $ID."
printf '%s' "$STATUS" | grep -q 'CLOSED' && refuse "$ID is already closed. Nothing to build."

BLOCKERS="$(bd show "$ID" 2>/dev/null | awk '/^DEPENDS ON/,/^$/' | grep -cE '→ ○|→ ◐' || true)"
[ "${BLOCKERS:-0}" -eq 0 ] || refuse "$ID still has $BLOCKERS unfinished dependency(ies). Run bd show $ID and clear them first."

# The payload leads with the skill invocation so it stands on its own. The
# routine's configured prompt is only a fallback: a fired run may replace it
# rather than supplement it, and the orchestration must arrive either way.
PAYLOAD="$(SPEC_FILE="$SPEC" BEAD="$ID" python3 -c '
import json, os
spec = open(os.environ["SPEC_FILE"]).read()
bead = os.environ["BEAD"]
text = (
    "Use the bead-pipeline skill to take this bead to a merged pull request.\n\n"
    + "bead: " + bead + "\n\n---SPEC---\n" + spec
)
print(json.dumps({"text": text}))')"

RESPONSE="$(mktemp)"
CODE="$(curl -sS -o "$RESPONSE" -w '%{http_code}' -X POST \
  "$API_BASE/v1/claude_code/routines/$ROUTINE_ID/fire" \
  -H "Authorization: Bearer $ROUTINE_TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: experimental-cc-routine-2026-04-01" \
  -H "Content-Type: application/json" \
  -d @- <<<"$PAYLOAD")"

if [ "$CODE" != "200" ] && [ "$CODE" != "201" ]; then
  BODY="$(head -c 400 "$RESPONSE")"
  rm -f "$RESPONSE"
  refuse "Firing the routine failed with HTTP $CODE. The bead was left untouched. Response: $BODY"
fi
rm -f "$RESPONSE"

bd update "$ID" --claim >/dev/null 2>&1

context "${SYNC:+$SYNC
}Routine fired for ${ID}; the spec in .specs/${ID}.md was sent and the bead is
now claimed. The cloud session will branch, implement, open a pull request and
review it. Tell the user it is running and that results arrive as a merged pull
request, or as one labelled needs-human. Do not start implementing ${ID} here."
