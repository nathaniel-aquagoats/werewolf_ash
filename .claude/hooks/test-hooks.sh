#!/usr/bin/env bash
# Unit tests for the pipeline hooks. Run: bash .claude/hooks/test-hooks.sh
#
# These stub bd, git, gh and curl on PATH, so nothing here touches the network,
# the beads database or the repository. The approve tests point ROUTINE_API_BASE
# at a stub curl and never send a real request.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

ok() {
  if [ "$1" = "$2" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $3"
    echo "      expected [$1] got [$2]"
  fi
}

# exit code of a hook fed one JSON payload
run() {
  printf '%s' "$2" | bash "$HERE/$1" >/tmp/hk.out 2>/tmp/hk.err
  echo $?
}
runpy() {
  printf '%s' "$2" | python3 "$HERE/$1" >/tmp/hk.out 2>/tmp/hk.err
  echo $?
}

echo "== protect-pipeline.py =="
P=protect-pipeline.py

# Build payloads with printf, never by interpolating braces into a quoted
# string: bash brace-expands {a,b,c} and silently splits the JSON into words.
j_file() { printf '{"hook_event_name":"PreToolUse","tool_name":"%s","agent_type":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" "$3"; }
j_file_main() { printf '{"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2"; }
j_bash() { printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","agent_type":"%s","tool_input":{"command":"%s"}}' "$1" "$2"; }

ok 2 "$(runpy $P "$(j_file Edit coder .claude/hooks/gates.sh)")" "subagent Edit under .claude is refused"
ok 2 "$(runpy $P "$(j_file Write coder CLAUDE.md)")" "subagent Write to CLAUDE.md is refused"
ok 2 "$(runpy $P "$(j_file Write coder AGENTS.md)")" "subagent Write to AGENTS.md is refused"
ok 2 "$(runpy $P "$(j_file Write coder .credo.exs)")" "subagent Write to .credo.exs is refused"
ok 2 "$(runpy $P "$(j_file Edit coder .beads/issues.jsonl)")" "subagent Edit under .beads is refused"
ok 0 "$(runpy $P "$(j_file Edit coder lib/werewolf_ash/games.ex)")" "subagent Edit to app code is allowed"
ok 0 "$(runpy $P "$(j_file Write coder .specs/current.md)")" "subagent Write to .specs is allowed"
ok 0 "$(runpy $P "$(j_file_main Write .claude/hooks/gates.sh)")" "main session may edit the pipeline"

# Bash: only write intent counts; reads must pass or the coder cannot orient.
ok 2 "$(runpy $P "$(j_bash coder 'echo x > .claude/settings.json')")" "subagent redirect into .claude is refused"
ok 2 "$(runpy $P "$(j_bash coder 'rm -f CLAUDE.md')")" "subagent rm of CLAUDE.md is refused"
ok 2 "$(runpy $P "$(j_bash coder "sed -i '' s/a/b/ .formatter.exs")")" "subagent in-place sed is refused"
ok 2 "$(runpy $P "$(j_bash coder 'cp /tmp/x .credo.exs')")" "subagent cp over .credo.exs is refused"
ok 0 "$(runpy $P "$(j_bash coder 'cat .claude/agents/coder.md')")" "subagent may read a brief"
ok 0 "$(runpy $P "$(j_bash coder 'grep -n Rules CLAUDE.md')")" "subagent may grep CLAUDE.md"
ok 0 "$(runpy $P "$(j_bash coder 'sed -n 1,40p .claude/skills/bead-pipeline/SKILL.md')")" "subagent may print a skill"
ok 0 "$(runpy $P "$(j_bash coder 'mix test')")" "subagent may run tests"
ok 0 "$(runpy $P "$(j_bash coder 'git push -u origin bead/x')")" "subagent may push"

# Redirects that only duplicate a file descriptor or hit /dev/null are reads.
ok 0 "$(runpy $P "$(j_bash coder 'bash .claude/hooks/session-start.sh 2>&1 | tail -20')")" "2>&1 on a pipeline read is not a write"
ok 0 "$(runpy $P "$(j_bash coder 'cat .claude/skills/bead-pipeline/SKILL.md 2>/dev/null')")" "2>/dev/null is not a write"
ok 0 "$(runpy $P "$(j_bash coder 'mix test >/dev/null 2>&1; grep -n Rules CLAUDE.md')")" ">/dev/null then a read is not a write"
ok 0 "$(runpy $P "$(j_bash coder 'grep -c x AGENTS.md >&2')")" ">&2 is not a write"
ok 2 "$(runpy $P "$(j_bash coder 'echo x 2>&1 > .claude/settings.json')")" "a real redirect after a dup is still refused"
ok 2 "$(runpy $P "$(j_bash coder 'echo x >> CLAUDE.md')")" "append to CLAUDE.md is still refused"
ok 2 "$(runpy $P "$(j_bash coder 'mix test 2>&1 | tee .claude/hooks/log.txt')")" "tee into .claude is still refused"

echo "== gates.sh =="
G=gates.sh
# On PreToolUse the gate must ignore anything that is not a push.
ok 0 "$(run $G '{"hook_event_name":"PreToolUse","cwd":"/nonexistent","tool_input":{"command":"ls -la"}}')" "PreToolUse ignores a non-push command"
ok 0 "$(run $G '{"hook_event_name":"PreToolUse","cwd":"/nonexistent","tool_input":{"command":"git status"}}')" "PreToolUse ignores git status"
# A missing cwd means no mix project, so the gate cannot run: it must not wedge.
ok 0 "$(run $G '{"hook_event_name":"PreToolUse","cwd":"/nonexistent","tool_input":{"command":"git push -u origin bead/x"}}')" "push outside a mix project is not blocked"

echo "== _payload.py =="
out="$(printf '%s' '{"a":"1","b":{"c":"2"}}' | python3 "$HERE/_payload.py" a b.c missing)"
ok "1
2
" "$out
" "dotted fields print in order, missing prints blank"
out="$(printf '%s' '{"cmd":"line one\nline two"}' | python3 "$HERE/_payload.py" cmd)"
ok "line one line two" "$out" "newlines inside a value are collapsed"

echo "== approve-bead.sh =="
A=approve-bead.sh
mk() { printf '{"hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$1"; }

# Unrelated prompts pass straight through.
ok 0 "$(run $A "$(mk 'what is the state of the games domain')")" "an ordinary prompt is untouched"
ok 0 "$(run $A "$(mk 'approve the plan please')")" "prose containing approve is not a gesture"

# reject makes no network call and injects context.
ok 0 "$(run $A "$(mk 'reject werewolf_ash-qss.3: rule 11 is wrong')")" "reject exits 0"
grep -q 'additionalContext' /tmp/hk.out || { FAIL=$((FAIL+1)); echo "FAIL: reject emits additionalContext"; }
grep -q 'rule 11 is wrong' /tmp/hk.out && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: reject carries the note"; }
python3 -c 'import json,sys; json.load(open("/tmp/hk.out"))' 2>/dev/null && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: reject output is valid JSON"; }

# approve refuses when the environment is not set up.
ok 2 "$(env -u ROUTINE_ID -u ROUTINE_TOKEN bash -c "printf '%s' '$(mk 'approve werewolf_ash-qss.3')' | bash '$HERE/$A'" 2>/tmp/hk.err; echo $?)" "approve without ROUTINE_ID refuses"
grep -qi 'ROUTINE_ID' /tmp/hk.err && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: names the missing variable"; }

# approve refuses when the spec is missing.
TMPREPO="$(mktemp -d)"
mkdir -p "$TMPREPO/.specs"
out=$(CLAUDE_PROJECT_DIR="$TMPREPO" ROUTINE_ID=x ROUTINE_TOKEN=y bash -c "printf '%s' '$(mk 'approve werewolf_ash-zzz.9')' | bash '$HERE/$A'" 2>/tmp/hk.err; echo $?)
ok 2 "$out" "approve with no spec file refuses"
grep -qi 'No spec' /tmp/hk.err && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: says the spec is missing"; }
rm -rf "$TMPREPO"

# The payload builder: valid JSON, leads with the skill line, carries the spec.
TMPSPEC="$(mktemp)"
printf '# t\n\n## Rules\n1. a rule with "quotes" and a \\ backslash\n' > "$TMPSPEC"
PAY="$(SPEC_FILE="$TMPSPEC" BEAD="werewolf_ash-qss.3" python3 -c '
import json, os
spec = open(os.environ["SPEC_FILE"]).read()
bead = os.environ["BEAD"]
text = (
    "Use the bead-pipeline skill to take this bead to a merged pull request.\n\n"
    + "bead: " + bead + "\n\n---SPEC---\n" + spec
)
print(json.dumps({"text": text}))')"
echo "$PAY" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: payload is valid JSON"; }
echo "$PAY" | python3 -c 'import json,sys; t=json.load(sys.stdin)["text"]; sys.exit(0 if t.startswith("Use the bead-pipeline skill") else 1)' && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: payload leads with the skill line"; }
echo "$PAY" | python3 -c 'import json,sys; t=json.load(sys.stdin)["text"]; sys.exit(0 if "bead: werewolf_ash-qss.3" in t and "---SPEC---" in t and "backslash" in t else 1)' && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: payload carries bead id and spec body"; }
rm -f "$TMPSPEC"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
