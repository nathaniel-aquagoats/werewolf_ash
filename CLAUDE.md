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
- Rules decisions already made: bodyguard picks by day and protects that night; hunter gets a 1h window after death then a random target; lynch is plurality with tie = no lynch; wolf kill is majority with tie = no kill; seer gets an immediate yes/no
- Chat: two channels per game, `village` (all living players) and `wolves` (living werewolves), open in every phase; dead players can read every channel but post in none; living non-wolves never see the wolves channel
- Alias style (enforced by `mix lint` via Credo): never group aliases (`alias Foo.{Bar, Baz}` -> one `alias` per line); never call a nested module fully qualified — `Foo.Bar.baz()` must be `alias Foo.Bar` + `Bar.baz()`. Elixir stdlib modules (`Enum`, `DateTime`, `Ecto`-style single names) are exempt per Credo's defaults
- Do not commit or push unless asked

## Bead lifecycle

Beads are specified locally, implemented in a claude.ai cloud routine, and
merged by the reviewer that checked them. The old worktree-and-coordinator
workflow is retired; `.claude/worktrees/` is no longer used.

```
spec-author  ->  you  ->  spec-reviewer  ->  approve  ->  cloud routine
                                                              |
                                          coder -> code-reviewer -> merge
                                                              |
                                     SessionStart sync closes the bead
```

### Locally

- `spec-author` (sonnet) turns a bead into `.specs/<bead-id>.md`: Goal, numbered
  testable Rules, Out of scope, Acceptance naming public functions, advisory
  Touches.
- You read and edit it. This is the point where the design is decided.
- `spec-reviewer` (opus) checks it against the bead and the settled decisions
  here. It never approves on your behalf.
- **`approve <bead-id>`** fires the routine with the whole spec. **`reject
  <bead-id>: <note>`** sends it back to the author and makes no network call.
  A `UserPromptSubmit` hook implements both; approval refuses if the bead is
  closed, unknown, has unfinished dependencies, or has no spec.

### In the cloud

The routine's prompt is only a pointer; the orchestration is
`.claude/skills/bead-pipeline/SKILL.md`, so it is versioned with the repo.

- `coder` (sonnet) implements the spec and only the spec, then pushes to
  `bead/<bead-id>`.
- `code-reviewer` (opus) breaks each rule in a scratch copy to prove a test
  catches it, hard-rejects anything outside the spec's scope, then rebases,
  re-runs the gates and squash-merges.
- Both agents run **synchronously**. The cloud session ends when the
  orchestrator's turn ends and does not wake for a backgrounded subagent, so a
  dispatched-and-forgotten reviewer strands the bead as an open, unreviewed PR.
- One retry on rejection. Then the PR is labelled `needs-human` and left open.
- Never a direct push to `main`.

**GitHub in the cloud is split.** Reads (`gh pr list`, `git fetch`) and
`git push` work, but the `gh` CLI's ambient token is rejected for writes and
`gh api` write paths are proxy-refused. PRs are created and merged with the
`mcp__github__*` tools instead. Deleting a remote branch is impossible from the
cloud (403); merged branches are pruned by the local sync.

### Back again

GitHub is the only channel home; the beads database never leaves this machine.
A `SessionStart` hook closes beads whose PR merged by parsing the bead id from
the PR title, deletes the spent spec file, prunes merged remote branches, and
lists anything labelled `needs-human`. **The squash title must be
`<bead-id>: <title>`** or the bead is stranded open.

### Specs are ephemeral

`.specs/` is gitignored and never committed. The copy that survives is the one
in the PR body, which is the audit trail. The local file is deleted when its PR
merges.

### Division of labour

Anything that changes the product — features, fixes, tests — becomes a bead and
goes through the pipeline. Anything about how the agents operate — briefs,
hooks, skills, this file, the beads graph — is done directly in the main tree,
because a bead worker is forbidden from touching it.

### Hooks

| Hook | Event | Does |
|---|---|---|
| `gates.sh` | `git push`, and `coder` finishing | `mix compile --warnings-as-errors`, `mix ash.codegen --check`, `mix lint`, `mix test`; exit 2 with the failing tail |
| `protect-pipeline.py` | Edit/Write/Bash | Refuses subagent writes to `.claude/`, `.beads/`, `CLAUDE.md`, `AGENTS.md`, `.credo.exs`, `.formatter.exs`. The main session is unaffected |
| `session-start.sh` | SessionStart | Starts Postgres, syncs merged beads, runs `bd prime` |

### Secrets and configuration

`ROUTINE_ID` and `ROUTINE_TOKEN` live in fish universal variables
(`set -Ux ROUTINE_ID trig_...`), never in the repo and never in chat. The
approve hook reads them from the environment and refuses if they are unset.

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
