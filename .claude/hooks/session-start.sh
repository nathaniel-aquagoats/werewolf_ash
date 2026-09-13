#!/usr/bin/env bash
# SessionStart: start Postgres if needed, sync beads and report the queue, and
# load beads context.
#
# A cloud environment snapshots its filesystem but not its processes, so the
# Postgres installed by .claude/cloud-setup.sh is present yet stopped when a
# session begins. Start it here or every gate run fails on the database.
#
# Cloud sessions have no beads install and no Dolt data, so a bare "bd prime"
# would fail there every time. Missing bd is normal, not an error.
#
# Both the sync summary and the beads context have to reach the model as one
# valid JSON payload, so they are merged rather than printed separately.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! pg_isready -h localhost -q 2>/dev/null; then
  if command -v pg_ctlcluster >/dev/null 2>&1; then
    pg_ctlcluster 16 main start >/dev/null 2>&1 || true
  elif command -v service >/dev/null 2>&1 && [ -x /etc/init.d/postgresql ]; then
    service postgresql start >/dev/null 2>&1 || true
  fi
fi

# Cloud sessions have no bd. Their cached environment setup can predate a
# dependency added since (swoosh, 2026-09-13), so fetch deps before any mix
# command needs them.
if ! command -v bd >/dev/null 2>&1; then
  if command -v mix >/dev/null 2>&1 && [ -f "${CLAUDE_PROJECT_DIR:-.}/mix.exs" ]; then
    (cd "${CLAUDE_PROJECT_DIR:-.}" && mix deps.get >/dev/null 2>&1) || true
  fi
  exit 0
fi

SYNC_TEXT="$(bash "$HERE/sync-beads.sh" 2>/dev/null)"
PRIME_JSON="$(bd prime --hook-json 2>/dev/null)"

SYNC_TEXT="$SYNC_TEXT" PRIME_JSON="$PRIME_JSON" python3 <<'PYEOF'
import json
import os

sync = os.environ.get("SYNC_TEXT", "").strip()
try:
    payload = json.loads(os.environ.get("PRIME_JSON") or "{}")
except ValueError:
    payload = {}

specific = payload.setdefault("hookSpecificOutput", {})
specific["hookEventName"] = "SessionStart"
context = specific.get("additionalContext") or ""

if sync:
    context = f"{sync}\n\n{context}" if context else sync

if not context:
    raise SystemExit(0)

specific["additionalContext"] = context
print(json.dumps(payload))
PYEOF
