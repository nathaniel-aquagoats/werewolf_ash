#!/usr/bin/env bash
# Close beads whose pull request has merged, and report what needs the owner.
#
# GitHub is the message bus between the cloud pipeline and this machine: the
# cloud can merge a PR but cannot touch the local Dolt database, so a bead stays
# open until this runs. Pull request titles carry the bead id, the same
# "<bead-id>: <title>" convention the squash commits already use. Spec pull
# requests are titled "spec(<bead-id>): ...", so merging one never closes a bead.
#
# Also prunes merged bead/ and spec/ branches, because a cloud session gets HTTP
# 403 when it tries to delete a remote branch, while this machine's credentials
# can.
#
# Then reports: PRs labelled needs-human (the queue is paused while any is
# open), spec PRs waiting on the owner with any comments newer than their last
# push, and the queue's next decision from next-bead.py.
#
# Idempotent: it closes only beads that are still open, so running it twice
# changes nothing the second time. Never fails its caller; every error is
# reported on stdout and the script still exits 0.

set -uo pipefail

PR_LIMIT=50
NET_TIMEOUT=20
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
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

  # The cloud cannot delete its own merged branch; do it here.
  case "$branch" in
  bead/* | spec/*)
    git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1 &&
      git push origin --delete "$branch" >/dev/null 2>&1
    ;;
  esac

  id="$(printf '%s' "$title" | grep -oE "^${BEAD_ID}:" | tr -d ':')"
  [ -n "$id" ] || continue

  # Only touch beads that are still open, so reruns are silent.
  # Assign first: under pipefail, "head -1" closing the pipe makes the whole
  # pipeline non-zero even when the pattern matched.
  headline="$(bd show "$id" 2>/dev/null | head -1)"
  if printf '%s' "$headline" | grep -qE 'OPEN|IN_PROGRESS'; then
    if bd close "$id" --reason="Merged in PR #${number}" >/dev/null 2>&1; then
      closed+=("$id (PR #${number})")
    fi
  fi
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
    echo "beads sync: pull requests waiting on you (labelled needs-human; the queue is paused):"
    cat "$TMP/stalled"
  fi
fi

# Spec PRs are where the owner reads and approves, often from a phone. A
# comment or review newer than the branch's last commit is feedback that
# nobody has acted on yet.
if with_timeout "$NET_TIMEOUT" "$TMP/specs" \
  gh pr list --state open --limit "$PR_LIMIT" \
  --json number,title,headRefName,comments,reviews,commits; then
  python3 - "$TMP/specs" <<'PYEOF' 2>/dev/null
import json
import sys

prs = [p for p in json.load(open(sys.argv[1])) if p.get("headRefName", "").startswith("spec/")]
if prs:
    print("beads sync: spec pull requests waiting on the owner to merge:")
for pr in sorted(prs, key=lambda p: p["number"]):
    commits = pr.get("commits") or []
    pushed = commits[-1].get("committedDate", "") if commits else ""
    times = [c.get("createdAt", "") for c in pr.get("comments") or []]
    times += [r.get("submittedAt", "") for r in pr.get("reviews") or []]
    new = sum(1 for t in times if t and t > pushed)
    note = "%d new comment(s) since the last push: act on them" % new if new else "no new comments"
    print("  #%d %s (%s)" % (pr["number"], pr["title"], note))
PYEOF
fi

# The queue: what the cloud starts next, and what is waiting on what.
with_timeout "$NET_TIMEOUT" "$TMP/queue" python3 "$HERE/next-bead.py"
case $? in
0 | 3)
  echo "beads queue:"
  sed 's/^/  /' "$TMP/queue"
  ;;
*) echo "beads queue: could not be read ($(head -c 160 "$TMP/queue" | tr '\n' ' '))" ;;
esac

exit 0
