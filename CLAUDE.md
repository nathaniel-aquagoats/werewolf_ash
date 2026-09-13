# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->


## Build & Test

Backend (Elixir 1.20, needs local Postgres 16 with `postgres`/`postgres`):

```bash
mix setup                         # ash.setup: create DB + run migrations
mix test                          # runs ash.setup --quiet first
mix test test/werewolf_ash/games_test.exs:42   # single file / single test
MIX_TEST_PARTITION=foo mix test   # private test DB werewolf_ash_testfoo (use one per worktree/agent)
mix ash.codegen <snake_case_name> # after ANY resource change: migrations + snapshots. Not igniter-backed: no --yes
mix ash.codegen --check           # CI-style check that snapshots match resources
mix compile --warnings-as-errors
mix lint                          # format --check-formatted + credo --strict; must be clean before a commit
mix phx.server                    # API on :4000, GraphiQL at /gql/playground, WS at /ws/gql
mix graphql.codegen               # after ANY graphql-facing change: writes mobile/schema.graphql, then runs
                                  # graphql-codegen in mobile/ (typed docs in mobile/src/gql). No DB needed. Commit the output
mix igniter.install <pkg> --yes   # any igniter task needs --yes: there is no TTY, prompts crash
mix usage_rules.sync --yes        # refresh AGENTS.md + .claude/skills after adding deps
```

Mobile (Expo SDK 57, in `mobile/`, Node 24 pinned by `mise.toml`):

```bash
cd mobile && npm install && npx expo start
```

Prod runtime requires `DATABASE_URL`, `SECRET_KEY_BASE`, `TOKEN_SIGNING_SECRET` (see `config/runtime.exs`).

## Architecture Overview

Real-time (wall-clock day/night) werewolf game. Ash 3 domain is the source of truth; every interface is a thin adapter over it.

- `lib/werewolf_ash/accounts` — AshAuthentication, `User` + `Token`. Sign-in is magic-link ONLY (no passwords, by decision); senders under `accounts/user/senders` only log until real email delivery lands
- `lib/werewolf_ash/games` — game domain (Game, Player, Phase, Action); rules live here, never in the API or mobile layers. `Game.state` is one of `lobby | day | night | hunter_pending | finished`; `Game.phase_ends_at` drives the scheduler
- Reactor sagas resolve phases (end of day / end of night, composing a win-check reactor); AshOban triggers on `Game` fire them when `phase_ends_at`/`hunter_deadline_at` pass
- `lib/werewolf_ash_web` — API-only Phoenix endpoint (Bandit): AshGraphql schema in `graphql_schema.ex`, served at `/gql`, subscriptions socket `graphql_socket.ex` at `/ws/gql`. No HTML, no LiveView, no controllers
- `mobile/` — Expo + React Native + TypeScript client, GraphQL client generated from the Ash schema. UI reference: the "Werewolf App Screens" design canvas linked on bead `o25.1`
- Domains are registered in `config/config.exs` `ash_domains` and in the GraphQL schema's domain list — both need editing when a domain is added
- `.claude/skills/` (`ash-framework`, `reactor`, `phoenix-api`) are generated from the deps' own usage rules; they are the reference for idioms, not this file

## Conventions & Patterns

- Learning project: prefer choices that exercise Ash/Reactor features over the cheapest path, and keep every task verifiable by `mix test`
- Use Ash generators (`mix ash.gen.domain`, `mix ash.gen.resource`, `mix ash.codegen`) rather than hand-writing resources; consult the `ash-framework` / `reactor` skills before domain changes
- Game rules must be testable without a clock or an interface: phase transitions are explicit actions (`end_day`, `end_night`), the scheduler only calls them
- A reactor run from inside an action (an `after_action` hook, or a change that calls `Reactor.run`) must run synchronously. Reactor defaults to `async?: true`, which runs steps in separate tasks on other database connections; those can't see the action's uncommitted writes, so a player the action just killed reads as alive and a win check decides wrongly. The Ecto test sandbox shares one connection, so no test catches this: set it explicitly (verify the option against `deps/reactor`) and check it by reading in review
- Rules decisions already made: bodyguard picks by day and protects that night, and may not protect the same player two days in a row; hunter gets a 1h window after death then a random target; lynch is plurality with tie = no lynch; the wolf kill is a single act, not a vote: any living werewolf may kill during the night, the first kill is the pack's one action for that night and is final (any later kill that night, by any wolf, is refused), and the victim dies immediately unless the bodyguard protected them that day, in which case the kill is spent and they survive; wolves coordinate in the wolves chat channel, not through a tally; the action type is :kill; seer gets an immediate yes/no
- Real time: the game follows the natural flow of time. Only the villagers' day vote is deliberative; every other action (the wolves' kill, the seer's investigation, the hunter's shot) takes effect the moment it happens. The bodyguard is the one exception that must plan ahead: protection is chosen by day and locked when night starts, which is what keeps it from racing the wolves' kill
- Deaths are announced: at the start of each day, everyone is told who died since the last announcement and what role each held, and a dead player's role becomes public from that announcement; at the start of each night, everyone is told night is starting
- Actions are used once: a player may take each action type once per phase, and a second attempt is refused rather than replacing the first. That includes the day vote, so a villager's vote is final once cast
- Chat: two channels per game, `village` (all living players) and `wolves` (living werewolves), open in every phase; dead players can read every channel but post in none; living non-wolves never see the wolves channel
- Alias style (enforced by `mix lint` via Credo): never group aliases (`alias Foo.{Bar, Baz}` -> one `alias` per line); never call a nested module fully qualified — `Foo.Bar.baz()` must be `alias Foo.Bar` + `Bar.baz()`. Elixir stdlib modules (`Enum`, `DateTime`, `Ecto`-style single names) are exempt per Credo's defaults
- Do not commit or push unless asked. Spec pull requests are the standing exception (see Bead lifecycle)

## Bead lifecycle

Beads are specified locally, approved by merging a spec pull request, built by
a claude.ai cloud routine that works through the approved specs, up to two at
a time, and merged by the reviewer that checked them. The old worktree-and-coordinator
workflow is retired; `.claude/worktrees/` is no longer used.

```
grill the owner -> spec-author -> spec-reviewer -> spec PR -> owner merges it
                                                                    |
      queue (any PR closing, daily, or by hand) -> coder -> code-reviewer -> merge
                                                                    |
                                               SessionStart sync closes the bead
```

### Locally

- **Grill the owner first.** Before filing a bead or starting a spec, ask
  thorough questions about the task and the design, each with a recommended
  answer, until the design is settled. The owner asked for this: a question
  answered up front is a spec revision round that never happens.
- `spec-author` (sonnet) writes `docs/specs/<bead-id>.md`: a `Depends on:`
  line, a **For the owner** card (what changes, decisions with
  recommendations, rule changes), then Goal, numbered testable Rules, Out of
  scope, Acceptance naming public functions, advisory Touches.
- `spec-reviewer` (opus) checks it against the bead, the code and the settled
  decisions here, including that the header and the owner card are true. It
  never approves. **Size the review to the bead:** beads that change domain
  rules, add or change authorization, add a migration, or rely on how Ash or
  AshGraphql behaves get the review. Beads that only change docs, config or
  wording skip it. If usage limits start to bite, move the middle tier to a
  Sonnet reviewer before dropping review.
- **The coordinator runs the loop quietly.** Authoring, one review pass and at
  most one revision happen without relaying each agent message to the owner.
  Only blockers go back to the author; the coordinator fixes nits directly in
  the spec; a second review happens only when there were blockers, and only on
  those.
- **The coordinator opens the spec PR.** Branch `spec/<bead-id>` from `main`,
  committing only the spec; title `spec(<bead-id>): <bead title>`; body a link
  to the file. The owner has given standing permission to push spec branches
  and open or update spec PRs without asking. That covers spec PRs only: never
  merge one, never push to `main`, and code or config changes still need the
  owner's go-ahead. Then send the owner a push notification with the link.
- **A spec PR title must not start `<bead-id>:`.** The sync closes a bead from
  that title shape, and the queue treats a commit subject of that shape on
  `main` as the bead being implemented.
- **The owner approves by merging**, which accepts the card's
  recommendations. A comment is a change request: the SessionStart report
  lists spec PRs with comments newer than their last push, and the coordinator
  acts on them, grilling the owner if a comment opens a design question,
  having the author revise, and pushing to the same PR.
- A merged spec changes only through another spec PR.

### The queue

The routine runs whenever a pull request closes (merged or not), once a day,
and by hand through its API (`.claude/hooks/fire-routine.sh [<bead-id>]`). What a run
does is decided by `.claude/hooks/next-bead.py`, from `main` and the open pull
requests:

- **Paused** for new starts while any PR labelled `needs-human` is open, until
  the owner looks. Beads already running finish.
- **Full** while two `bead/*` PRs are open: at most two beads run at once.
- Otherwise it starts the **earliest-merged spec** that is not implemented,
  whose `Depends on:` beads are all implemented, and that can run beside the
  bead already running. Implemented means `main` has a commit subject starting
  `<bead-id>:`, which every bead squash has and so do beads finished before
  this flow, or the spec is stamped `Implemented in PR #N.`
- **Two beads run together** only when neither depends on the other and their
  specs' Touches sections name no common file under `lib/` or `priv/`.
  Generated migrations and resource snapshots don't count, because a rebase
  regenerates them. A spec whose Touches names no file is treated as touching
  everything. A later spec may start ahead of an earlier one that conflicts.
- Each run claims at most one bead. A merge, the daily run or a manual fire
  fills a free slot, and `next-bead.py --claimed` settles two runs racing for
  the same one.
- **A named bead** skips queue order and nothing else, and resumes that bead's
  own open PR if it has one. When the owner says to implement a specific bead,
  or to retry a `needs-human` PR after looking at it, the coordinator runs
  `fire-routine.sh <bead-id>`. Closing a `needs-human` PR instead unpauses the
  queue, and the close itself starts a run; the bead restarts from its
  leftover branch.
- Every PR that closes costs a routine run against the daily cap, even when
  the queue is busy and the run stops at once, so merging a burst of spec PRs
  spends a run each.

### In the cloud

The routine's prompt is only a pointer; the orchestration is
`.claude/skills/bead-pipeline/SKILL.md`, so it is versioned with the repo.

- The orchestrator claims a bead by opening its PR, `<bead-id>: <title>` from
  `bead/<bead-id>`, before any work, confirms with `next-bead.py --claimed`
  that no other run took the slot, then stamps the spec on that branch with
  the PR number.
- `coder` (sonnet) implements the spec and only the spec, then pushes.
- `code-reviewer` (opus) breaks each rule in a scratch copy to prove a test
  catches it, hard-rejects anything outside the spec's scope, then rebases,
  re-runs the gates and squash-merges.
- Both agents are run synchronously by preference, so a run is one legible
  sequence. Backgrounding does work — the session wakes when a subagent
  finishes — but the run must never end with the PR open and unreviewed.
- One retry on rejection. Then the PR is labelled `needs-human`, left open, and
  new starts pause.
- A rebase conflict because another bead merged first is not a rejection: the
  reviewer reports it, the coder rebases and regenerates, and the reviewer
  looks again. It does not use the retry; after two such hand-backs the PR
  goes to `needs-human`.
- Never a direct push to `main`.

**GitHub in the cloud is split.** Reads (`gh pr list`, `git fetch`) and
`git push` work, but the `gh` CLI's ambient token is rejected for writes and
`gh api` write paths are proxy-refused. PRs are created, updated, closed and
merged with the `mcp__github__*` tools instead. Deleting a remote branch is
impossible from the cloud (403); merged branches are pruned by the local sync.

### Back again

GitHub is the only channel home; the beads database never leaves this machine.
`sync-beads.sh`, run by the `SessionStart` hook, closes beads whose PR merged by
parsing the bead id from the PR title, prunes merged `bead/` and `spec/`
branches, and reports PRs labelled `needs-human`, spec PRs waiting on the owner
(with any new comments), and the queue's next decision. **The squash title must
be `<bead-id>: <title>`** or the bead is stranded open and everything that
depends on it waits.

### Specs live on main

`docs/specs/` is the record of what each bead was asked to do, and specs are
never deleted. A bead PR stamps its spec `Implemented in PR #N.` and the stamp
lands with the merge. Subagents other than `spec-author` are refused writes to
`docs/specs/`, so a coder cannot move the goalposts it is reviewed against; the
stamp is written by the cloud orchestrator, which is the main session.

### Division of labour

Anything that changes the product — features, fixes, tests — becomes a bead and
goes through the pipeline. Anything about how the agents operate — briefs,
hooks, skills, this file, the beads graph — is done directly in the main tree,
because a bead worker is forbidden from touching it.

### Hooks and scripts

All under `.claude/hooks/`. Tests: `bash .claude/hooks/test-hooks.sh`.

| File | Runs | Does |
|---|---|---|
| `gates.sh` | hook: `git push`, and `coder` finishing | `mix compile --warnings-as-errors`, `mix ash.codegen --check`, `mix lint`, `mix test`; exit 2 with the failing tail |
| `protect-pipeline.py` | hook: Edit/Write/Bash | Refuses subagent writes to `.claude/`, `.beads/`, `CLAUDE.md`, `AGENTS.md`, `.credo.exs`, `.formatter.exs`, and to `docs/specs/` unless the subagent is `spec-author`. A named teammate reports its name, not its type, so **name spec-author teammates `spec-author-<suffix>`** or they cannot write specs. The main session is unaffected |
| `session-start.sh` | hook: SessionStart | Starts Postgres, runs `sync-beads.sh`, runs `bd prime` |
| `next-bead.py` | cloud orchestrator; sync report | Prints the queue's decision: `next`, `continue`, `won`/`lost`, `paused`, `full`, `idle`, or why a named bead can't start |
| `fire-routine.sh` | coordinator, by hand | Starts the routine, optionally naming a bead |

### Secrets and configuration

`ROUTINE_ID` and `ROUTINE_TOKEN` live in fish universal variables
(`set -Ux ROUTINE_ID trig_...`), never in the repo and never in chat.
`fire-routine.sh` reads them from the environment and refuses if they are unset.

Two routines run the same saved prompt and configuration: Sonnet, the
`Agent` and `Skill` tools (the orchestrator dispatches the coder and reviewer
as subagents), no connectors, and no pinned output branch.

- **"Coding after Spec Accepted"** has the GitHub trigger on pull requests
  closing. It needs the Claude GitHub App installed on the repository.
- **"Spec implementation Routine"** has the daily schedule at 15:00 UTC and the
  API trigger that `fire-routine.sh` uses. Never give it a GitHub trigger too,
  or every merge starts two runs.

A routine created in the claude.ai form attaches every connector and pins a
`claude/...` output branch by default; clear both, and check `Agent` and
`Skill` are allowed. Duplicate runs are safe, since `next-bead.py --claimed`
settles races, but they spend the daily cap. When attaching a GitHub trigger
through `RemoteTrigger` `create_webhook_trigger`, the body that validates is
`{"routine_trigger_id": "trig_...", "source": "github", "hook_type": "app",
"scope_id": "<owner>/<repo>", "events": ["pull_request.closed"]}`; the filter
format is undocumented, so the trigger is unfiltered and `next-bead.py`
decides what each run does. Its saved prompt points at the
skill and allows acting on exactly one line of fire text, `bead: <bead-id>`.

The cloud environment's setup script is mirrored at `.claude/cloud-setup.sh`
for review; the live copy is pasted into the environment at claude.ai. Edit
both together. It needs Network access set to Custom with `repo.hex.pm` and
`builds.hex.pm` added.

### Test standard (the coder writes to it, the code-reviewer enforces it)

- Coverage by rule, not by line: every rule/acceptance item in the bead has at least one test that fails if that rule is removed, plus its negative case (wrong role, dead player, wrong phase, bad token...). Edge cases only where the rules make them meaningful (ties, boundaries, DST, zero players)
- Every public function gets tested: the domain code interface and GraphQL, and also public changes, validations, preparations, reactor modules/steps, and helpers (`Game.Clock`, `Message.Visibility`, ...). Unit-test those directly on their own contract; then integration-test the rule end to end once through the code interface or GraphQL. Private functions are covered through their callers, not tested directly
- Not brittle, not exhaustive: assert on behaviour and on error class/field, not on exact error message text, whole-struct equality, generated ids, timestamps, log output, or ordering that is not itself a rule. A public function gets a handful of tests — its main contract, its negative case, and the edge cases the rules make meaningful — typically 2–5, never a 20-case matrix of near-duplicate inputs. Prefer one well-chosen example per behaviour over many variations of the same behaviour
- Deterministic: injected `now`, no `sleep`, no dependence on test order; `async: true` unless the test genuinely needs the shared DB
- Reviewer checks, always: (1) take **every** numbered rule in the spec, break it in a scratch copy, and confirm a test fails — a rule with no failing test is a rejection, and reading a test and judging it sufficient is not this check; (2) look for assertions that a rename, reworded message, or extra field would break — flag them as nits with the looser assertion to use; (3) reject any change outside the spec's scope, however good it is
