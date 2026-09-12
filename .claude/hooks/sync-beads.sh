#!/usr/bin/env bash
# Close beads whose pull request has merged, and surface the ones that stalled.
#
# GitHub is the message bus between the cloud pipeline and this machine: the
# cloud can merge a PR but cannot touch the local Dolt database, so a bead stays
# open until this runs. Pull request titles carry the bead id, the same
# "<bead-id>: <title>" convention the squash commits already use.
#
# Also prunes merged bead branches, because a cloud session gets HTTP 403 when
# it tries to delete a remote branch, while this machine's credentials can.
#
# Idempotent: it closes only beads that are still open, so running it twice
# changes nothing the second time. Never fails its caller; every error is
# reported on stdout and the script still exits 0.

set -uo pipefail

PR_LIMIT=50
NET_TIMEOUT=20
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SPEC_DIR="$REPO_ROOT/.specs"
BEAD_ID='[A-Za-z0-9_]+-[A-Za-z0-9]+(\.[0-9]+)*'

cd "$REPO_ROOT" 2>/dev/null || exit 0
command -v bd >/dev/null 2>&1 || exit 0
command -v gh >/dev/null 2>&1 || exit 0

# Portable timeout: macOS has no coreutils timeout by default.
with_timeout() {
  local secs="$1" out="$2"
  shift 2
  "$@" >"$out" 2>&1 &
  local pid=$!
  (
    sleep "$secs"
    kill -9 "$pid" 2>/dev/null
  ) &
  local watcher=$!
  wait "$pid" 2>/dev/null
  local rc=$?
  kill -9 "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  return "$rc"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! with_timeout "$NET_TIMEOUT" "$TMP/merged" \
  gh pr list --state merged --limit "$PR_LIMIT" --json title,number,headRefName; then
  echo "beads sync: could not reach GitHub, skipped ($(head -c 120 "$TMP/merged"))"
  exit 0
fi

closed=()
while IFS=$'\t' read -r number title branch; do
  [ -n "$title" ] || continue
  id="$(printf '%s' "$title" | grep -oE "^${BEAD_ID}:" | tr -d ':')"
  [ -n "$id" ] || continue

  # Only touch beads that are still open, so reruns are silent.
  # Assign first: under pipefail, "head -1" closing the pipe makes the whole
  # pipeline non-zero even when the pattern matched.
  headline="$(bd show "$id" 2>/dev/null | head -1)"
  if printf '%s' "$headline" | grep -qE 'OPEN|IN_PROGRESS'; then
    if bd close "$id" --reason="Merged in PR #${number}" >/dev/null 2>&1; then
      closed+=("$id (PR #${number})")
      rm -f "$SPEC_DIR/$id.md"
    fi
  fi

  # The cloud cannot delete its own merged branch; do it here.
  case "$branch" in
  bead/*)
    git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1 &&
      git push origin --delete "$branch" >/dev/null 2>&1
    ;;
  esac
done < <(python3 -c '
import json, sys
for pr in json.load(open(sys.argv[1])):
    print("\t".join([str(pr["number"]), pr["title"], pr.get("headRefName", "")]))
' "$TMP/merged" 2>/dev/null)

if [ "${#closed[@]}" -gt 0 ]; then
  printf 'beads sync: closed %s\n' "$(
    IFS=', '
    echo "${closed[*]}"
  )"
fi

# Anything the pipeline gave up on needs a human; say so first thing.
if with_timeout "$NET_TIMEOUT" "$TMP/stalled" \
  gh pr list --state open --label needs-human --limit "$PR_LIMIT" \
  --json number,title --jq '.[] | "  #\(.number) \(.title)"'; then
  if [ -s "$TMP/stalled" ]; then
    echo "beads sync: pull requests waiting on you (labelled needs-human):"
    cat "$TMP/stalled"
  fi
fi

exit 0
