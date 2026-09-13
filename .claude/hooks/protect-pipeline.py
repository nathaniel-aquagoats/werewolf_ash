#!/usr/bin/env python3
"""Keep bead workers out of the pipeline that judges them.

A worker under context pressure can "fix" a failing gate by loosening the gate,
rewriting a reviewer brief, or deleting a Credo rule. Nothing in a bead needs
those files, so writes to them are refused with a pointer to the PR body.

Specs under docs/specs/ are protected the same way: a coder that edits its spec
has moved the goalposts it is reviewed against. The spec author is the one
subagent that writes them.

agent_type is the subagent's type for an unnamed subagent, but a teammate
spawned with a name reports its name instead ("author-qss5", seen 2026-09-12),
so a type check alone refused every named spec author. Spec authors are
therefore recognised by type or by the name prefix "spec-author-"; spawn them
with that prefix.

Only calls made from inside a subagent are blocked: a payload carries
agent_type when a subagent made the call and omits it in the main session, so
the coordinator can still edit the pipeline directly, and the cloud orchestrator
can still stamp a spec with its PR number. PIPELINE_EDIT=1 lifts the block for a
session that is deliberately changing the pipeline.

Wired as PreToolUse on Edit|Write|NotebookEdit|Bash. Exit 2 refuses the call.
"""

import json
import os
import re
import sys

PROTECTED = (
    ".claude/",
    ".beads/",
    "CLAUDE.md",
    "AGENTS.md",
    ".credo.exs",
    ".formatter.exs",
)

SPECS = "docs/specs/"
SPEC_WRITER = "spec-author"


def writes_specs(agent):
    return agent == SPEC_WRITER or agent.startswith(SPEC_WRITER + "-")

# Redirects that write nothing the worker owns: file-descriptor duplication
# (2>&1, >&2) and the bit bucket (>/dev/null, 2>/dev/null). Stripped before the
# write-intent check, or a plain read like "cat SKILL.md 2>&1 | tail" is refused
# because the ">" in "2>&1" looks like a file write. Seen 2026-09-12 on PR #4.
HARMLESS_REDIRECT = re.compile(r"(\d*>&\d+|\d*>>?\s*/dev/null)")

# Shell constructs that modify a file rather than read it.
WRITE_INTENT = re.compile(
    r"(>>?|\btee\b|\bsed\b[^|;]*\s-i|\bcp\b|\bmv\b|\brm\b|\bln\b|\btruncate\b"
    r"|\bchmod\b|\bdd\b|\bpatch\b|\bapply\b)"
)

# The write verbs other than a redirect. When a command's only writes are
# redirects, only the redirect targets are checked: "git show
# origin/spec/x:docs/specs/x.md > /tmp/old.md" reads a spec and writes /tmp, and
# refusing it stopped a spec reviewer diffing a revision (2026-09-13).
OTHER_WRITE = re.compile(
    r"(\btee\b|\bsed\b[^|;]*\s-i|\bcp\b|\bmv\b|\brm\b|\bln\b|\btruncate\b"
    r"|\bchmod\b|\bdd\b|\bpatch\b|\bapply\b)"
)
REDIRECT_TARGET = re.compile(r"\d*>>?\s*([^\s;|&<>]+)")

REFUSAL = (
    "Blocked: {target} is part of the agent pipeline, a spec, or lint config, "
    "which is out of scope for every bead. Do not edit hooks, agent briefs, "
    "skills, specs under docs/specs, CLAUDE.md, AGENTS.md, Credo or formatter "
    "config, or the beads database. If one of them is genuinely wrong, say so "
    "in the pull request body and leave the file alone."
)


def protected_hit(text, patterns):
    if not text:
        return None
    for pattern in patterns:
        if pattern.endswith("/"):
            found = pattern in text or text.startswith(pattern.rstrip("/"))
        else:
            # Match the filename as a whole path segment, not as a substring.
            found = re.search(r"(^|[\s\"'/=]){}($|[\s\"';:,)])".format(re.escape(pattern)), text)
        if found:
            return pattern
    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    if os.environ.get("PIPELINE_EDIT") == "1":
        return 0

    # Absent agent_type means the main session, which may edit the pipeline.
    agent = payload.get("agent_type")
    if not agent:
        return 0

    patterns = PROTECTED if writes_specs(agent) else PROTECTED + (SPECS,)
    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}

    if tool == "Bash":
        command = HARMLESS_REDIRECT.sub(" ", tool_input.get("command", ""))
        if not WRITE_INTENT.search(command):
            return 0
        if OTHER_WRITE.search(command):
            target = protected_hit(command, patterns)
        else:
            target = next(
                (hit for dest in REDIRECT_TARGET.findall(command) if (hit := protected_hit(dest, patterns))),
                None,
            )
    else:
        target = protected_hit(tool_input.get("file_path", ""), patterns)

    if target:
        print(REFUSAL.format(target=target) + " (agent_type: %s)" % agent, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
