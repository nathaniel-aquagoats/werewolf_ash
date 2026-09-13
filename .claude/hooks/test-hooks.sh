#!/usr/bin/env bash
# Unit tests for the pipeline hooks. Run: bash .claude/hooks/test-hooks.sh
#
# Nothing here touches the network, the beads database or this repository:
# fire-routine.sh runs dry, and next-bead.py reads a throwaway git repository
# and a JSON file standing in for GitHub.

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
ok 2 "$(runpy $P "$(j_file Write coder docs/specs/werewolf_ash-qss.5.md)")" "coder Write to a spec is refused"
ok 2 "$(runpy $P "$(j_file Edit code-reviewer /home/user/werewolf_ash/docs/specs/werewolf_ash-qss.5.md)")" "code-reviewer Edit to a spec is refused"
ok 0 "$(runpy $P "$(j_file Write spec-author docs/specs/werewolf_ash-qss.5.md)")" "spec-author may write a spec"
ok 0 "$(runpy $P "$(j_file Edit spec-author-qss5 docs/specs/werewolf_ash-qss.5.md)")" "a named spec-author teammate may write a spec"
ok 2 "$(runpy $P "$(j_file Edit author-qss5 docs/specs/werewolf_ash-qss.5.md)")" "a teammate without the spec-author prefix may not"
ok 2 "$(runpy $P "$(j_file Edit spec-authority docs/specs/werewolf_ash-qss.5.md)")" "the prefix must be the whole word"
ok 2 "$(runpy $P "$(j_file Write spec-author .claude/agents/spec-author.md)")" "spec-author may not edit its own brief"
ok 0 "$(runpy $P "$(j_file_main Edit docs/specs/werewolf_ash-qss.5.md)")" "main session may stamp a spec"
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
ok 2 "$(runpy $P "$(j_bash coder "sed -i '' s/a/b/ docs/specs/werewolf_ash-qss.5.md")")" "coder in-place sed on a spec is refused"
ok 0 "$(runpy $P "$(j_bash coder 'cat docs/specs/werewolf_ash-qss.5.md')")" "coder may read its spec"
ok 0 "$(runpy $P "$(j_bash spec-reviewer-x 'git show origin/spec/a-b.1:docs/specs/a-b.1.md > /tmp/old.md && diff /tmp/old.md docs/specs/a-b.1.md')")" "reading a spec into /tmp is not a write to the spec"
ok 2 "$(runpy $P "$(j_bash coder 'cat /tmp/x > docs/specs/werewolf_ash-qss.5.md')")" "a redirect into a spec is still refused"
ok 2 "$(runpy $P "$(j_bash coder "cat /tmp/x > 'docs/specs/werewolf_ash-qss.5.md'")")" "a quoted redirect target is still checked"
ok 2 "$(runpy $P "$(j_bash coder 'grep x docs/specs/a.md > /tmp/y; cp /tmp/y docs/specs/a.md')")" "another write verb still checks the whole command"

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

# Pushes that change nothing outside docs/specs/ skip the gates; code changes do not.
GR="$(mktemp -d)"
gg() { git -C "$GR" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
gg init -q
printf 'this is not a real mix project\n' >"$GR/mix.exs"
gg add mix.exs && gg commit -q -m base
gg update-ref refs/remotes/origin/main HEAD
push_payload() { printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_input":{"command":"git push -u origin bead/x"}}' "$GR"; }
gate() { printf '%s' "$(push_payload)" | env -u CLAUDE_PROJECT_DIR bash "$HERE/gates.sh" >/dev/null 2>&1; echo $?; }
gg commit -q --allow-empty -m "werewolf_ash-x.1: start"
ok 0 "$(gate)" "an empty claim commit push skips the gates"
mkdir -p "$GR/docs/specs" && printf 'Implemented in PR #1.\n' >"$GR/docs/specs/werewolf_ash-x.1.md"
gg add docs/specs && gg commit -q -m "werewolf_ash-x.1: stamp spec with PR #1"
ok 0 "$(gate)" "a spec-stamp push skips the gates"
mkdir -p "$GR/lib" && printf 'defmodule X do end\n' >"$GR/lib/x.ex"
ok 2 "$(gate)" "an untracked code file in the same command still runs the gates"
rm -rf "$GR"

echo "== _payload.py =="
out="$(printf '%s' '{"a":"1","b":{"c":"2"}}' | python3 "$HERE/_payload.py" a b.c missing)"
ok "1
2
" "$out
" "dotted fields print in order, missing prints blank"
out="$(printf '%s' '{"cmd":"line one\nline two"}' | python3 "$HERE/_payload.py" cmd)"
ok "line one line two" "$out" "newlines inside a value are collapsed"

echo "== fire-routine.sh =="
F="$HERE/fire-routine.sh"
fire() { env -u ROUTINE_ID -u ROUTINE_TOKEN "$@" >/tmp/hk.out 2>/tmp/hk.err; echo $?; }
DRY="ROUTINE_ID=x ROUTINE_TOKEN=y FIRE_ROUTINE_DRY_RUN=1"

ok 1 "$(fire bash "$F" werewolf_ash-qss.3)" "fire without ROUTINE_ID refuses"
ok 0 "$(grep -q ROUTINE_ID /tmp/hk.err; echo $?)" "the refusal names the missing variable"
ok 1 "$(fire $DRY bash "$F" 'not a bead')" "a malformed bead id refuses"
ok 1 "$(fire $DRY bash "$F" werewolf_ash-qss.3 werewolf_ash-qss.4)" "two bead ids refuse"
ok 0 "$(fire $DRY bash "$F" werewolf_ash-qss.3)" "a bead id builds a request"
ok '{"text": "bead: werewolf_ash-qss.3"}' "$(cat /tmp/hk.out)" "the request carries one bead line and nothing else"
ok 0 "$(fire $DRY bash "$F")" "no bead id builds a request"
ok '{}' "$(cat /tmp/hk.out)" "running the queue sends no fire text"

echo "== next-bead.py =="
NB="$HERE/next-bead.py"
R="$(mktemp -d)"
PRS="$(mktemp)"
n=0
g() { git -C "$R" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
# Each commit is a minute after the last, so merge order is unambiguous.
commit() {
  n=$((n + 1))
  local d="$((1767225600 + n * 60)) +0000"
  GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d" g commit -q --allow-empty -m "$1"
}
# spec <id> <header> <touches body>
spec() {
  mkdir -p "$R/docs/specs"
  printf '# %s: a title\n\n%s\n\n## Goal\nx\n\n## Touches\nAdvisory only.\n%s\n' "$1" "$2" "$3" >"$R/docs/specs/$1.md"
  g add "docs/specs/$1.md"
  commit "spec($1): a title"
}
prs() { printf '%s' "$1" >"$PRS"; }
pr() { printf '{"number":%s,"title":"%s: x","headRefName":"bead/%s","labels":[%s]}' "$1" "$2" "$2" "${3:-}"; }
nb() { (cd "$R" && NEXT_BEAD_REF=HEAD NEXT_BEAD_NO_FETCH=1 NEXT_BEAD_OPEN_PRS="$PRS" python3 "$NB" "$@" >/tmp/nb.out 2>&1; echo $?); }
first() { head -1 /tmp/nb.out; }
has() { grep -qx "$1" /tmp/nb.out && echo yes || echo no; }

g init -q
commit "werewolf_ash-aaa.1: a bead finished before specs lived on main (#1)"
spec werewolf_ash-bbb.1 "Depends on: werewolf_ash-ccc.1" "- lib/werewolf_ash/b.ex"
spec werewolf_ash-ccc.1 "Depends on: werewolf_ash-aaa.1" "- \`lib/werewolf_ash/shared.ex:12\`"
spec werewolf_ash-ddd.1 "Depends on: none" "- lib/werewolf_ash/shared.ex, test/werewolf_ash/d_test.exs"
spec werewolf_ash-eee.1 "No dependency line at all" "- lib/werewolf_ash/e.ex"
spec werewolf_ash-fff.1 "Depends on: none

Implemented in PR #9." "- lib/werewolf_ash/f.ex"
spec werewolf_ash-iii.1 "Depends on: none" "- lib/werewolf_ash/i.ex
- priv/resource_snapshots/repo/games/shared.json"
spec werewolf_ash-jjj.1 "Depends on: none" "Nothing specific yet."
spec werewolf_ash-kkk.1 "Depends on: none" "- \`test/werewolf_ash/games/action_test.exs\` only"
printf '# Specs\n' >"$R/docs/specs/README.md"
g add docs/specs/README.md
commit "docs: specs readme"
printf '# werewolf_ash-ggg.1: t\n\nDepends on: none\n' >"$R/docs/specs/werewolf_ash-ggg.1.md"
prs '[]'

ok 0 "$(nb)" "a ready spec is picked"
ok "next werewolf_ash-ccc.1" "$(first)" "earliest-merged ready spec wins; one with an unmerged dependency is skipped"
ok yes "$(has 'waiting werewolf_ash-bbb.1 on werewolf_ash-ccc.1')" "the skipped spec says what it waits on"
ok yes "$(has 'queued werewolf_ash-ddd.1')" "later ready specs are listed as queued"
ok 0 "$(grep -q '^malformed werewolf_ash-eee.1' /tmp/nb.out; echo $?)" "a spec with no Depends on line is reported, not started"
ok 1 "$(grep -q 'fff\|ggg\|README' /tmp/nb.out; echo $?)" "stamped, uncommitted and non-spec files are not queued"

ok 3 "$(nb --check werewolf_ash-bbb.1)" "a named bead with an unmerged dependency does not start"
ok "waiting werewolf_ash-bbb.1 on werewolf_ash-ccc.1" "$(first)" "and says what it waits on"
ok 3 "$(nb --check werewolf_ash-fff.1)" "a named stamped bead does not start"
ok "implemented werewolf_ash-fff.1" "$(first)" "and says it is implemented"
ok 3 "$(nb --check werewolf_ash-zzz.1)" "a named bead with no spec on main does not start"
ok "nospec werewolf_ash-zzz.1" "$(first)" "and says there is no spec"
ok 3 "$(nb --check werewolf_ash-eee.1)" "a named bead with a malformed spec does not start"
ok 0 "$(nb --check werewolf_ash-ddd.1)" "a named ready bead starts out of queue order"
ok "next werewolf_ash-ddd.1" "$(first)" "and is the one named"
ok 1 "$(nb --check 'not a bead')" "a malformed argument is an error"

# One bead running: a second may start beside it only if they share no source file.
prs "[$(pr 5 werewolf_ash-ccc.1)]"
ok 0 "$(nb)" "a second bead may start while one is running"
ok "next werewolf_ash-iii.1" "$(first)" "a later spec with no shared source file starts ahead of an earlier one that conflicts"
ok yes "$(has 'running werewolf_ash-ccc.1 #5')" "the running bead is listed"
ok yes "$(has 'conflicts werewolf_ash-ddd.1 with werewolf_ash-ccc.1: lib/werewolf_ash/shared.ex')" "a shared lib file is a conflict, named"
ok yes "$(has 'conflicts werewolf_ash-jjj.1 with werewolf_ash-ccc.1: (files unknown)')" "a spec whose Touches names no file conflicts with everything"
ok yes "$(has 'queued werewolf_ash-kkk.1')" "a test-only spec shares no source file, so it can run beside anything"
ok 3 "$(nb --check werewolf_ash-ddd.1)" "a named bead that conflicts with a running one does not start"
ok "conflicts werewolf_ash-ddd.1 with werewolf_ash-ccc.1: lib/werewolf_ash/shared.ex" "$(first)" "and says with what"
ok 0 "$(nb --check werewolf_ash-ccc.1)" "naming a running bead resumes its own PR"
ok "continue #5" "$(first)" "resume names the PR"
ok 0 "$(nb --claimed werewolf_ash-ccc.1)" "the only claim wins"
ok "won #5" "$(first)" "won names the PR"

# Two running: the queue is full.
prs "[$(pr 5 werewolf_ash-ccc.1),$(pr 6 werewolf_ash-iii.1)]"
ok 3 "$(nb)" "two running beads fill the queue"
ok "full #5, #6" "$(first)" "full names both PRs"
ok 3 "$(nb --check werewolf_ash-ddd.1)" "a named bead cannot start when the queue is full"
ok 0 "$(nb --claimed werewolf_ash-iii.1)" "a claim beside one non-conflicting earlier PR wins"

# Races: a claim loses to earlier PRs that already fill the slots or conflict with it.
prs "[$(pr 5 werewolf_ash-ccc.1),$(pr 6 werewolf_ash-iii.1),$(pr 7 werewolf_ash-ddd.1)]"
ok 3 "$(nb --claimed werewolf_ash-ddd.1)" "a third claim loses"
ok "lost #7 to #5, #6" "$(first)" "and names the PRs that hold the slots"
prs "[$(pr 5 werewolf_ash-ccc.1),$(pr 6 werewolf_ash-ddd.1)]"
ok 3 "$(nb --claimed werewolf_ash-ddd.1)" "a claim that conflicts with an earlier PR loses"
ok "lost #6 to #5 (werewolf_ash-ccc.1: lib/werewolf_ash/shared.ex)" "$(first)" "and says why"
ok 1 "$(nb --claimed werewolf_ash-bbb.1)" "claiming with no open PR is an error"

# A running bead with no spec on main might touch anything.
prs "[$(pr 9 werewolf_ash-zzz.1)]"
ok 3 "$(nb)" "nothing starts beside a running bead whose files are unknown"
ok "idle" "$(first)" "that is idle, not full"

# needs-human stops new starts but not the beads already running.
prs "[$(pr 4 werewolf_ash-ccc.1 '{"name":"needs-human"}')]"
ok 3 "$(nb)" "a needs-human PR pauses new starts"
ok "paused #4 werewolf_ash-ccc.1: x" "$(first)" "the pause names the PR"
ok 0 "$(nb --check werewolf_ash-ccc.1)" "naming the stuck bead resumes its own PR"

prs '[{"number":6,"title":"spec(werewolf_ash-hhh.1): x","headRefName":"spec/werewolf_ash-hhh.1","labels":[]}]'
ok 0 "$(nb)" "an open spec PR does not occupy a slot"

# The cloud reads PRs from the REST pulls API, whose shape differs from gh pr list.
prs '[{"number":5,"title":"werewolf_ash-ccc.1: x","head":{"ref":"bead/werewolf_ash-ccc.1"},"labels":[{"id":1,"name":"needs-human"}]}]'
ok 3 "$(nb)" "a REST-shaped needs-human bead PR pauses the queue"
ok "paused #5 werewolf_ash-ccc.1: x" "$(first)" "REST head.ref and label names are read"

prs '[]'
commit "werewolf_ash-ccc.1: the dependency lands (#10)"
ok 0 "$(nb)" "a merged dependency releases the waiting spec"
ok "next werewolf_ash-bbb.1" "$(first)" "which goes ahead of later specs, in merge order"

for b in bbb ddd iii jjj kkk; do commit "werewolf_ash-$b.1: done"; done
ok 3 "$(nb)" "nothing ready is idle"
ok "idle" "$(first)" "idle says so"

# A spec PR merged with a merge commit: its place in the queue is when it
# reached main, and its branch commits say nothing about being implemented.
base="$(g rev-parse --abbrev-ref HEAD)"
g checkout -q -b side
spec werewolf_ash-lll.1 "Depends on: none" "- lib/werewolf_ash/l.ex"
commit "werewolf_ash-lll.1: start"
g checkout -q "$base"
spec werewolf_ash-mmm.1 "Depends on: none" "- lib/werewolf_ash/m.ex"
n=$((n + 1))
d="$((1767225600 + n * 60)) +0000"
GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d" g merge -q --no-ff side -m "Merge pull request #20 from spec/werewolf_ash-lll.1"
ok 0 "$(nb)" "specs merged with a merge commit are queued"
ok "next werewolf_ash-mmm.1" "$(first)" "queue order is when a spec reached main, not when it was written"
ok yes "$(has 'queued werewolf_ash-lll.1')" "a start commit inside a merged branch does not mark the bead implemented"

echo 'not json' >"$PRS"
ok 1 "$(nb)" "unreadable pull requests are an error, never a start"
rm -rf "$R" "$PRS"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
