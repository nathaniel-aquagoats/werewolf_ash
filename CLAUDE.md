# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

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

Backend (Elixir, needs local Postgres 16 with `postgres`/`postgres`):

```bash
mix setup            # ash.setup: create DB + run migrations
mix test             # runs ash.setup --quiet first
mix ash.codegen <name>   # after any resource change: generates migrations + snapshots
mix phx.server       # API on :4000, GraphiQL at /gql/playground
mix usage_rules.sync # refresh AGENTS.md + .claude/skills after adding deps
```

Mobile (Expo, in `mobile/`, Node 24 via mise):

```bash
cd mobile && npm install && npx expo start
```

## Architecture Overview

Real-time (wall-clock day/night) werewolf game. Ash 3 domain is the source of truth; every interface is a thin adapter over it.

- `lib/werewolf_ash/accounts` — AshAuthentication (password strategy), `User` + `Token`
- `lib/werewolf_ash/games` — game domain (Game, Player, Phase, Action); rules live here, never in the API or mobile layers
- Reactor sagas resolve phases (end of day / end of night / win check); AshOban triggers fire them on schedule
- `lib/werewolf_ash_web` — API-only Phoenix endpoint: AshGraphql at `/gql`, subscriptions over `/ws/gql`. No HTML, no LiveView
- `mobile/` — Expo + React Native + TypeScript client, GraphQL client generated from the Ash schema

## Conventions & Patterns

- Learning project: prefer choices that exercise Ash/Reactor features over the cheapest path, and keep every task verifiable by `mix test`
- Use Ash generators (`mix ash.gen.domain`, `mix ash.gen.resource`, `mix ash.codegen`) rather than hand-writing resources; consult the `ash-framework` / `reactor` skills before domain changes
- Game rules must be testable without a clock or an interface: phase transitions are explicit actions (`end_day`, `end_night`), the scheduler only calls them
- Rules decisions already made: bodyguard picks by day and protects that night; hunter gets a 1h window after death then a random target; lynch is plurality with tie = no lynch; wolf kill is majority with tie = no kill; seer gets an immediate yes/no
- Do not commit or push unless asked
