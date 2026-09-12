#!/usr/bin/env python3
"""Decide which bead the cloud pipeline starts next.

A spec is approved by merging its spec pull request, which adds
docs/specs/<bead-id>.md to main. This reads main and the open pull requests
and prints one decision on its first line:

  next <bead-id>        start this bead                            exit 0
  continue #<n>         --check only: resume this bead's open PR   exit 0
  paused #<n> <title>   a needs-human PR is open; start nothing    exit 3
  busy #<n> <branch>    a bead is already in flight; start nothing exit 3
  idle                  nothing is ready                           exit 3
  <reason> <bead-id>    --check only: why that bead cannot start   exit 3
                        (nospec, implemented, malformed, waiting)
  error <detail>        the inputs could not be read               exit 1

Later lines describe the rest of the queue: "queued <id>", "waiting <id> on
<deps>", "malformed <id>: ...".

The queue runs in the order specs were merged. A bead is implemented when main
has a commit whose subject starts "<bead-id>:" (every squash-merged bead PR
does, and so do beads finished before this flow existed) or when its spec
carries the stamp "Implemented in PR #N". A dependency is met by the same test.

Usage:
  next-bead.py                 pick from the queue
  next-bead.py --check <id>    may this bead start, or resume, now?

Test seams: NEXT_BEAD_REF (default origin/main), NEXT_BEAD_NO_FETCH=1, and
NEXT_BEAD_OPEN_PRS, a JSON file standing in for `gh pr list`.
"""

import json
import os
import re
import subprocess
import sys

BEAD_ID = r"[A-Za-z0-9_]+-[A-Za-z0-9]+(?:\.[0-9]+)*"
SPEC_DIR = "docs/specs"
STAMP = re.compile(r"^Implemented in PR #\d+", re.M)
DEPENDS = re.compile(r"^Depends on:[ \t]*(.*)$", re.M)
# The dependency line sits under the title; don't let a rule quoting the
# phrase further down stand in for a missing header.
HEADER_LINES = 40


class InputError(Exception):
    pass


def git(*args):
    result = subprocess.run(["git", *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise InputError("git %s: %s" % (" ".join(args), result.stderr.strip()[:200]))
    return result.stdout


def open_prs():
    path = os.environ.get("NEXT_BEAD_OPEN_PRS")
    if path:
        with open(path) as handle:
            return json.load(handle)
    result = subprocess.run(
        ["gh", "pr", "list", "--state", "open", "--limit", "100",
         "--json", "number,title,headRefName,labels"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise InputError("gh pr list: " + result.stderr.strip()[:200])
    return json.loads(result.stdout)


def implemented_ids(ref):
    ids = set()
    for subject in git("log", "--format=%s", ref).splitlines():
        match = re.match("(" + BEAD_ID + "):", subject)
        if match:
            ids.add(match.group(1))
    return ids


def specs(ref):
    """(merged_at, bead_id, text) for every spec on ref, earliest merge first."""
    found = []
    for path in git("ls-tree", "--name-only", ref, SPEC_DIR + "/").splitlines():
        match = re.fullmatch("(" + BEAD_ID + r")\.md", os.path.basename(path))
        if not match:
            continue
        added = git("log", ref, "--diff-filter=A", "--format=%ct", "-1", "--", path).strip()
        found.append((int(added or 0), match.group(1), git("show", "%s:%s" % (ref, path))))
    found.sort()
    return found


def depends_on(text):
    header = "\n".join(text.splitlines()[:HEADER_LINES])
    match = DEPENDS.search(header)
    if not match:
        return None
    return re.findall(BEAD_ID, match.group(1))


def assess(bead, text, implemented):
    if bead in implemented or STAMP.search(text):
        return "implemented", []
    deps = depends_on(text)
    if deps is None:
        return "malformed", []
    unmet = [dep for dep in deps if dep not in implemented]
    return ("waiting", unmet) if unmet else ("ready", [])


def labels(pr):
    return {label.get("name") for label in pr.get("labels") or []}


def blocked(prs):
    """Why nothing new may start, or None."""
    stuck = sorted((p for p in prs if "needs-human" in labels(p)), key=lambda p: p["number"])
    if stuck:
        return "paused #%d %s" % (stuck[0]["number"], stuck[0].get("title", ""))
    busy = sorted((p for p in prs if p.get("headRefName", "").startswith("bead/")),
                  key=lambda p: p["number"])
    if busy:
        return "busy #%d %s" % (busy[0]["number"], busy[0]["headRefName"])
    return None


def check(bead, prs, queue, implemented):
    for pr in prs:
        if pr.get("headRefName") == "bead/" + bead:
            print("continue #%d" % pr["number"])
            return 0
    reason = blocked(prs)
    if reason:
        print(reason)
        return 3
    entry = next((item for item in queue if item[1] == bead), None)
    if entry is None:
        print("nospec " + bead)
        return 3
    state, unmet = assess(bead, entry[2], implemented)
    if state == "ready":
        print("next " + bead)
        return 0
    print("%s %s%s" % (state, bead, " on " + ", ".join(unmet) if unmet else ""))
    return 3


def pick(prs, queue, implemented):
    ready, notes = [], []
    for _, bead, text in queue:
        state, unmet = assess(bead, text, implemented)
        if state == "ready":
            ready.append(bead)
        elif state == "waiting":
            notes.append("waiting %s on %s" % (bead, ", ".join(unmet)))
        elif state == "malformed":
            notes.append("malformed %s: no 'Depends on:' line under the title" % bead)

    reason = blocked(prs)
    if reason:
        print(reason)
        queued, code = ready, 3
    elif ready:
        print("next " + ready[0])
        queued, code = ready[1:], 0
    else:
        print("idle")
        queued, code = [], 3
    for bead in queued:
        print("queued " + bead)
    for note in notes:
        print(note)
    return code


def main(argv):
    named = None
    if argv[:1] == ["--check"] and len(argv) == 2 and re.fullmatch(BEAD_ID, argv[1]):
        named = argv[1]
    elif argv:
        print("error usage: next-bead.py [--check <bead-id>]")
        return 1

    ref = os.environ.get("NEXT_BEAD_REF", "origin/main")
    try:
        if os.environ.get("NEXT_BEAD_NO_FETCH") != "1":
            git("fetch", "--quiet", "origin", "main")
        prs = open_prs()
        implemented = implemented_ids(ref)
        queue = specs(ref)
    except (InputError, ValueError, OSError) as error:
        print("error " + str(error).replace("\n", " "))
        return 1

    if named:
        return check(named, prs, queue, implemented)
    return pick(prs, queue, implemented)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
