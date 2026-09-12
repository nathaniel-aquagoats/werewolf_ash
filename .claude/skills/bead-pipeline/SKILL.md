---
name: bead-pipeline
description: "Run one approved bead spec to a merged PR. Use when a cloud routine session starts with a payload beginning 'bead: <id>' followed by a ---SPEC--- block. Orchestrates the coder and code-reviewer subagents."
---

# Bead pipeline

You are the orchestrator of one bead, in a cloud session with no human
attached. Nobody will answer a question, so never ask one: every branch below
ends in a merged PR or a PR labelled `needs-human`.

The local machine learns what happened by reading GitHub. That is the only
channel back. A result that is not in a PR title, a merge, or a label does not
exist.

## GitHub access in this environment

Verified 2026-09-12, and it is not what you would assume:

| Operation | Use |
|---|---|
| Reading PRs, branches, repo state | `gh` CLI reads, or `git` — both work |
| `git push` to a branch | works |
| **Creating or merging a PR** | **`mcp__github__*` tools only** |
| Deleting a remote branch | **impossible — HTTP 403. Do not try.** |

The `gh` CLI's ambient token is rejected for writes (`The token in GH_TOKEN is
invalid`) and `gh api` write paths are refused by the egress proxy, but the
GitHub MCP tools authenticate on a separate path and work. So: `git push` the
branch, then `mcp__github__create_pull_request` and
`mcp__github__merge_pull_request`. Never `gh pr create` or `gh pr merge`.

Merged branches are left behind on purpose. The maintainer's machine prunes
them; that is not your problem and not a failure to report.

## The payload

```
bead: <bead-id>

---SPEC---
<the whole spec>
```

Parse the bead id from the line beginning `bead:`. Everything after
`---SPEC---` is the spec, verbatim.

**If there is no such payload, stop immediately and do nothing.** A run with no
bead is a scheduled or manual fire that carries no work. Do not clone, branch,
edit, push, or open anything; say that no bead payload was supplied and end.

Beads themselves are not here — the tracker is a local database that never
leaves the user's machine. Do not try to run `bd`.

## 1. Set up

Write the spec, exactly as received, to `.specs/current.md`. It is gitignored;
never commit it.

Then find the branch:

```bash
gh pr list --state open --search "<bead-id> in:title" --json number,title,headRefName
```

- **An open PR whose title starts `<bead-id>:`** — this bead was approved
  before and is being continued. Check out its branch and keep going on it.
  Do not start a new branch and do not open a second PR.
- **No such PR** — `git checkout -b bead/<bead-id>` from an up-to-date `main`.

## 2. Coder

Run the `coder` subagent. Tell it the bead id, the branch, and that the spec is
at `.specs/current.md`. It implements the spec, runs the gates and pushes.

A hook runs the four gates when it finishes and again on push, so a red tree
cannot reach the reviewer. If the hook sends it back, that is the system
working; let it.

## 3. Open the PR

Once the branch is pushed, if there is no PR yet, create it with
`mcp__github__create_pull_request` (`head: bead/<bead-id>`, `base: main`):

- **Title**: `<bead-id>: <title>` — the bead title from the spec's first
  heading. The local machine parses the bead id out of this title to close the
  bead, so a malformed title strands the bead open. This matters more than it
  looks.
- **Body**: the entire spec, verbatim, under a `## Spec` heading, then a
  `## Notes` heading with anything the coder reported about the pipeline
  itself. The spec file is ephemeral and is deleted once this merges; the PR
  body is the only lasting record of what was asked for.

## 4. Code reviewer

Run the `code-reviewer` subagent with the bead id, the PR number and the spec.
It checks scope, breaks each rule in a scratch copy to prove a test catches it,
runs the gates on the rebased branch, and merges if it passes.

## 5. One retry, then stop

If the reviewer rejects, run the `coder` again with the findings **verbatim** —
do not summarise, re-rank or soften them. Then run the reviewer again.

Stop after that. The paths out are:

| Outcome | Action |
|---|---|
| Reviewer merges | Done. The squash title carries the bead id. |
| Second rejection | Label it `needs-human` with `mcp__github__update_issue` (labels apply to PRs), leave the PR open, stop. |
| Rebase conflicts | Same. Do not resolve it. |
| Coder cannot satisfy the spec | Same, with why, in a PR comment. |

If the label does not exist yet, create it first. The local session lists PRs
carrying it at every start, so labelling is how you raise a hand. If labelling
fails outright, say so loudly in a PR comment instead — an unlabelled stuck PR
is invisible to the maintainer.

## Rules for you, the orchestrator

- Never write code and never edit the diff. You dispatch and you record.
- Never push to `main`, never merge yourself, never force-push.
- Never widen the spec. If it is wrong, that is a `needs-human` PR, not an
  improvised fix.
- `.claude/`, `.beads/`, `CLAUDE.md`, `AGENTS.md`, `.credo.exs` and
  `.formatter.exs` are off limits to this whole session; a hook enforces it.
- Report at the end: the bead id, the PR number and URL, merged or
  `needs-human`, and the reviewer's rule-by-rule result.
