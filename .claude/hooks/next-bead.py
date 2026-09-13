#!/usr/bin/env python3
"""Decide which bead the cloud pipeline starts next.

A spec is approved by merging its spec pull request, which adds
docs/specs/<bead-id>.md to main. This reads main and the open pull requests
and prints one decision on its first line:

  next <bead-id>        start this bead                                  exit 0
  continue #<n>         --check only: resume this bead's open PR         exit 0
  won #<n>              --claimed only: this run keeps its new PR        exit 0
  paused #<n> <title>   a needs-human PR is open; start nothing new      exit 3
  full #<n>, #<m>       MAX_IN_FLIGHT beads are already running          exit 3
  idle                  nothing can start now                            exit 3
  lost #<n> to ...      --claimed only: close this run's PR and stop     exit 3
  <reason> <bead-id>    --check only: why that bead cannot start         exit 3
                        (nospec, implemented, malformed, waiting, conflicts)
  error <detail>        the inputs could not be read                     exit 1

Later lines describe the rest: "running <id> #<n>", "queued <id>",
"waiting <id> on <deps>", "conflicts <id> with <id>: <files>",
"malformed <id>: ...".

The queue runs in the order specs were merged, up to MAX_IN_FLIGHT beads at
once. A bead may start alongside the ones already running only when neither
depends on the other and their specs' Touches sections name no common file
under lib/ or priv/. Generated migrations and resource snapshots don't count,
because a rebase regenerates them. A spec whose Touches names no file at all
is treated as touching everything, and so is a running bead whose spec is not
on main. A later spec may start ahead of an earlier one that conflicts.

A bead is implemented when main has a commit whose subject starts
"<bead-id>:" (every squash-merged bead PR does, and so do beads finished
before this flow existed) or when its spec carries the stamp
"Implemented in PR #N". A dependency is met by the same test.

A needs-human PR stops new starts only. Beads already running finish.

Usage:
  next-bead.py                  pick from the queue
  next-bead.py --check <id>     may this bead start, or resume, now?
  next-bead.py --claimed <id>   after opening this bead's PR: did this run
                                get the slot, or did an earlier PR take it?

Test seams: NEXT_BEAD_REF (default origin/main), NEXT_BEAD_NO_FETCH=1, and
NEXT_BEAD_OPEN_PRS, a JSON file standing in for `gh pr list`.
"""

import json
import os
import re
import subprocess
import sys

MAX_IN_FLIGHT = 2
BEAD_ID = r"[A-Za-z0-9_]+-[A-Za-z0-9]+(?:\.[0-9]+)*"
SPEC_DIR = "docs/specs"
STAMP = re.compile(r"^Implemented in PR #\d+", re.M)
DEPENDS = re.compile(r"^Depends on:[ \t]*(.*)$", re.M)
# The dependency line sits under the title; don't let a rule quoting the
# phrase further down stand in for a missing header.
HEADER_LINES = 40
TOUCHES = re.compile(r"^## Touches[^\n]*\n(.*?)(?=^## |\Z)", re.M | re.S)
SOURCE_PATH = re.compile(r"(?<![\w./-])((?:lib|priv|test)/[\w./-]*[\w/])")
GENERATED = ("priv/repo/migrations/", "priv/resource_snapshots/")
UNKNOWN = "(files unknown)"


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


def touches(text):
    """Source paths a spec's Touches names, or None when it names no file at all."""
    match = TOUCHES.search(text)
    paths = set(SOURCE_PATH.findall(match.group(1))) if match else set()
    if not paths:
        return None
    return {p for p in paths if not p.startswith("test/") and not p.startswith(GENERATED)}


def shared_files(mine, theirs):
    if mine is None or theirs is None:
        return [UNKNOWN]
    shared = set()
    for a in mine:
        for b in theirs:
            if a == b or (a.endswith("/") and b.startswith(a)) or (b.endswith("/") and a.startswith(b)):
                shared.add(max(a, b, key=len))
    return sorted(shared)


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


def paused(prs):
    stuck = sorted((p for p in prs if "needs-human" in labels(p)), key=lambda p: p["number"])
    if stuck:
        return "paused #%d %s" % (stuck[0]["number"], stuck[0].get("title", ""))
    return None


def in_flight(prs, queue):
    """(bead_id, pr_number, spec_text or None) for each open bead PR, oldest first."""
    texts = {bead: text for _, bead, text in queue}
    running = []
    for pr in sorted(prs, key=lambda p: p["number"]):
        head = pr.get("headRefName", "")
        if head.startswith("bead/"):
            bead = head[len("bead/"):]
            running.append((bead, pr["number"], texts.get(bead)))
    return running


def full(running):
    return "full " + ", ".join("#%d" % number for _, number, _ in running)


def conflict(bead, text, running):
    """(other_bead, why) for the first running bead this one may not run beside."""
    mine = touches(text)
    for other, _, other_text in running:
        if other_text is None:
            return other, UNKNOWN
        if other in (depends_on(text) or []) or bead in (depends_on(other_text) or []):
            return other, "(dependency)"
        shared = shared_files(mine, touches(other_text))
        if shared:
            return other, ", ".join(shared)
    return None


def check(bead, prs, queue, implemented):
    for pr in prs:
        if pr.get("headRefName") == "bead/" + bead:
            print("continue #%d" % pr["number"])
            return 0
    stuck = paused(prs)
    if stuck:
        print(stuck)
        return 3
    running = in_flight(prs, queue)
    if len(running) >= MAX_IN_FLIGHT:
        print(full(running))
        return 3
    entry = next((item for item in queue if item[1] == bead), None)
    if entry is None:
        print("nospec " + bead)
        return 3
    state, unmet = assess(bead, entry[2], implemented)
    if state != "ready":
        print("%s %s%s" % (state, bead, " on " + ", ".join(unmet) if unmet else ""))
        return 3
    clash = conflict(bead, entry[2], running)
    if clash:
        print("conflicts %s with %s: %s" % (bead, clash[0], clash[1]))
        return 3
    print("next " + bead)
    return 0


def claimed(bead, prs, queue):
    running = in_flight(prs, queue)
    mine = next((item for item in running if item[0] == bead), None)
    if mine is None:
        print("error no open pull request from bead/" + bead)
        return 1
    earlier = [item for item in running if item[1] < mine[1]]
    if len(earlier) >= MAX_IN_FLIGHT:
        print("lost #%d to %s" % (mine[1], ", ".join("#%d" % item[1] for item in earlier)))
        return 3
    if mine[2] is None:
        clash = (earlier[0][0], UNKNOWN) if earlier else None
    else:
        clash = conflict(bead, mine[2], earlier)
    if clash:
        number = next(item[1] for item in earlier if item[0] == clash[0])
        print("lost #%d to #%d (%s: %s)" % (mine[1], number, clash[0], clash[1]))
        return 3
    print("won #%d" % mine[1])
    return 0


def pick(prs, queue, implemented):
    running = in_flight(prs, queue)
    busy = {bead for bead, _, _ in running}
    stuck = paused(prs)
    no_slot = len(running) >= MAX_IN_FLIGHT
    chosen, notes = None, []
    for _, bead, text in queue:
        if bead in busy:
            continue
        state, unmet = assess(bead, text, implemented)
        if state == "waiting":
            notes.append("waiting %s on %s" % (bead, ", ".join(unmet)))
        elif state == "malformed":
            notes.append("malformed %s: no 'Depends on:' line under the title" % bead)
        elif state == "ready":
            clash = conflict(bead, text, running)
            if clash:
                notes.append("conflicts %s with %s: %s" % (bead, clash[0], clash[1]))
            elif chosen is None and not stuck and not no_slot:
                chosen = bead
            else:
                notes.append("queued " + bead)

    if stuck:
        print(stuck)
        code = 3
    elif no_slot:
        print(full(running))
        code = 3
    elif chosen:
        print("next " + chosen)
        code = 0
    else:
        print("idle")
        code = 3
    for bead, number, _ in running:
        print("running %s #%d" % (bead, number))
    for note in notes:
        print(note)
    return code


def main(argv):
    mode, named = None, None
    if len(argv) == 2 and argv[0] in ("--check", "--claimed") and re.fullmatch(BEAD_ID, argv[1]):
        mode, named = argv
    elif argv:
        print("error usage: next-bead.py [--check <bead-id> | --claimed <bead-id>]")
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

    if mode == "--check":
        return check(named, prs, queue, implemented)
    if mode == "--claimed":
        return claimed(named, prs, queue)
    return pick(prs, queue, implemented)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
