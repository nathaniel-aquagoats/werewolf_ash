---
name: verify
description: "Verify a code change: run verify.sh, the definition of a green tree (compile, codegen checks, format, credo, tests, Dialyzer), then prove requirement by requirement that the requested feature is implemented. Use when asked to verify, check or confirm a change, a bead or a feature, or before calling work done. Takes a bead id or a description of the feature as its argument. Reports; never edits."
---

# Verify

Two steps, in order: the script decides whether the tree is green, then you
decide whether the change does what was asked.

You report and nothing else. Do not edit, format, regenerate or fix anything,
not even a one-line mechanical failure: a verifier that changes what it
verifies can make a check pass by weakening it. Whoever called you decides what
to fix and runs you again.

## 1. The script

```bash
bash .claude/skills/verify/verify.sh
```

Run it from the tree being verified; a worktree is checked against its own test
database. It takes minutes, and the first Dialyzer run on a machine builds a PLT
for several more, so give it a long timeout.

Its exit code is the only definition of green. Running some of the checks
yourself and concluding from those is not a substitute, and a `SKIP` line is
the script's decision, never yours.

Each `FAIL` line names a file holding that check's full output. The printed
tail is only the last lines and can miss the cause (a compile warning prints
long before the test summary), so search the file before you report.

If it exits non-zero, report the failing checks with their output and stop.
There is no feature check on a red tree: a test that proves a requirement
proves nothing while the suite around it is failing.

## 2. The feature

**The requirement.** Take it from the first of these that exists:

1. The argument is a bead id: the numbered rules in `docs/specs/<bead-id>.md`.
2. Any other argument: that text.
3. No argument: what was asked for earlier in this conversation.

Say in one line what you took the requirement to be. If you can find none, ask;
do not infer one from the diff, because a requirement read off the code always
matches the code.

**The change.** Everything since the branch left `main`, plus uncommitted and
untracked files:

```bash
git diff "$(git merge-base HEAD origin/main)"
git ls-files --others --exclude-standard
```

**The evidence.** Break the requirement into numbered points (a spec's rules
are already that list). For each point find:

- the code that implements it, as `file:line`
- the test that exercises it, as `file:line`

Then run the named tests together, `mix test path:line path:line`, to confirm
each one exists and runs rather than being excluded or skipped.

A point is **proven** only when its test would fail if the point were removed.
Judge that by reading the assertions. It is **unproven** when:

- no test exercises it
- a test runs the code but asserts nothing about this behaviour
- the point is a refusal (wrong role, dead player, wrong phase) and only the
  allowed case is tested
- the code is missing or does something else

Reading is the standard here. Breaking each rule in a scratch copy to watch a
test go red is the `code-reviewer` agent's job on a bead PR, not this skill's.

Some changes have nothing a test can exercise (documentation, wording, an
agent brief). Say so for that point and cite the diff as the evidence.

**Unrequested changes.** List every change in the diff that no point asked
for. A test updated because a requirement changed the behaviour it depended on
is a consequence, not an unrequested change.

## The report

Lead with the verdict. It is `VERIFIED` only when the script exited 0 and every
point is proven; anything else is `NOT VERIFIED`, followed by what is missing.

Then:

- the requirement, in one line, and where you took it from
- a table with one row per point: the point, the code, the test, proven or
  unproven with the reason
- unrequested changes, or "none"
- the script's PASS/FAIL/SKIP lines as printed
