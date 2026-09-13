#!/usr/bin/env bash
# Start the cloud pipeline by hand.
#
#   fire-routine.sh               run the queue now
#   fire-routine.sh <bead-id>     start or resume that bead, out of queue order
#
# The queue normally starts itself: every merged pull request and a daily
# schedule run the routine, which picks the next ready spec. Use this when the
# owner asks for a specific bead to be implemented, to retry a needs-human PR
# after the owner has looked at it, or when a dropped GitHub event has left the
# queue idle.
#
# Naming a bead skips queue order and nothing else: the routine still refuses a
# bead with no merged spec or with unmerged dependencies, and still starts
# nothing when two beads are running or the bead shares files with one that is. The routine's saved prompt acts
# on exactly one line of fire text, "bead: <bead-id>"; fire text otherwise
# arrives labelled as untrusted and is ignored.
#
# Secrets come from the environment only. In fish:
#   set -Ux ROUTINE_ID   trig_...
#   set -Ux ROUTINE_TOKEN sk-ant-...
#
# FIRE_ROUTINE_DRY_RUN=1 prints the request body instead of sending it.

set -uo pipefail

API_BASE="${ROUTINE_API_BASE:-https://api.anthropic.com}"
BEAD_ID='^[A-Za-z0-9_]+-[A-Za-z0-9]+(\.[0-9]+)*$'

die() {
  echo "fire-routine: $1" >&2
  exit 1
}

[ "$#" -le 1 ] || die "usage: fire-routine.sh [<bead-id>]"
ID="${1:-}"
if [ -n "$ID" ]; then
  printf '%s' "$ID" | grep -qE "$BEAD_ID" || die "not a bead id: $ID"
fi

[ -n "${ROUTINE_ID:-}" ] || die "ROUTINE_ID is not set. Set it with: set -Ux ROUTINE_ID trig_..."
[ -n "${ROUTINE_TOKEN:-}" ] || die "ROUTINE_TOKEN is not set. Set it with: set -Ux ROUTINE_TOKEN sk-ant-..."

PAYLOAD="$(BEAD="$ID" python3 -c '
import json, os
bead = os.environ["BEAD"]
print(json.dumps({"text": "bead: " + bead} if bead else {}))')"

if [ "${FIRE_ROUTINE_DRY_RUN:-}" = "1" ]; then
  printf '%s\n' "$PAYLOAD"
  exit 0
fi

RESPONSE="$(mktemp)"
trap 'rm -f "$RESPONSE"' EXIT
CODE="$(curl -sS -o "$RESPONSE" -w '%{http_code}' -X POST \
  "$API_BASE/v1/claude_code/routines/$ROUTINE_ID/fire" \
  -H "Authorization: Bearer $ROUTINE_TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: experimental-cc-routine-2026-04-01" \
  -H "Content-Type: application/json" \
  -d @- <<<"$PAYLOAD")"

if [ "$CODE" != "200" ] && [ "$CODE" != "201" ]; then
  die "firing the routine failed with HTTP $CODE: $(head -c 400 "$RESPONSE")"
fi

python3 -c '
import json, sys
body = json.load(open(sys.argv[1]))
print("routine started: " + body.get("claude_code_session_url", "(no session url in response)"))
' "$RESPONSE" 2>/dev/null || echo "routine started"
