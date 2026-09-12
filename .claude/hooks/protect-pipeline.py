#!/usr/bin/env python3
"""Keep bead workers out of the pipeline that judges them.

A worker under context pressure can "fix" a failing gate by loosening the gate,
rewriting a reviewer brief, or deleting a Credo rule. Nothing in a bead needs
those files, so writes to them are refused with a pointer to the PR body.

Only calls made from inside a subagent are blocked: a payload carries
agent_type when a subagent made the call and omits it in the main session, so
the coordinator can still edit the pipeline directly. PIPELINE_EDIT=1 lifts the
block for a session that is deliberately changing the pipeline.

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

# Shell constructs that modify a file rather than read it.
WRITE_INTENT = re.compile(
    r"(>>?|\btee\b|\bsed\b[^|;]*\s-i|\bcp\b|\bmv\b|\brm\b|\bln\b|\btruncate\b"
    r"|\bchmod\b|\bdd\b|\bpatch\b|\bapply\b)"
)

REFUSAL = (
    "Blocked: {target} is part of the agent pipeline or lint config, which is "
    "out of scope for every bead. Do not edit hooks, agent briefs, skills, "
    "CLAUDE.md, AGENTS.md, Credo or formatter config, or the beads database. "
    "If one of them is genuinely wrong, say so in the pull request body and "
    "leave the file alone."
)


def protected_hit(text):
    if not text:
        return None
    for pattern in PROTECTED:
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
    if not payload.get("agent_type"):
        return 0

    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}

    if tool == "Bash":
        command = tool_input.get("command", "")
        if not WRITE_INTENT.search(command):
            return 0
        target = protected_hit(command)
    else:
        target = protected_hit(tool_input.get("file_path", ""))

    if target:
        print(REFUSAL.format(target=target), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
