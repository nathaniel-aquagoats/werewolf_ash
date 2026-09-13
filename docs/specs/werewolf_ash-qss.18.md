# werewolf_ash-qss.18: Action target validity: target alive, and actor/target/phase in the same game

Implemented in PR #17.

Depends on: none

## For the owner

**What changes.** Players can no longer vote to lynch, kill, investigate, or
protect someone who is already dead — those attempts are now rejected. The
game also checks that the player taking an action and the player they target
are actually seated in the same game. The bodyguard still cannot protect the
same person on two consecutive days.

**Decisions.**
1. Should the bodyguard's "no repeat protection" check compare only against
   the day right before, or against every day they've ever protected?
   **Decided:** only the immediately preceding day — protecting the same
   person again is fine once at least one day has passed in between.
2. On a game's very first day — or when a game happens to start at night, so
   its first day isn't its first phase — there is no earlier protection to
   compare against yet. **Decided:** allow any target in that case; the
   restriction only applies once there is a previous day to compare to.
3. Should a hunter's shot also be blocked from targeting a dead player right
   now? **Decided:** not yet — the pending-hunter mechanics
   (werewolf_ash-qss.7) haven't been designed, so this spec leaves the shot's
   targeting rules untouched for now.

**Rule changes.** Adds to the settled rules: "A vote, kill, investigation, or
protection may not target a player who is not alive, and the actor and
target must both be seated in the game the action belongs to." Clarifies the
existing bodyguard rule: "may not protect the same player two days in a row"
means specifically the immediately preceding day phase — a gap of one day is
enough to protect them again.

## Assumptions

The bead's rules are marked SETTLED by the owner, but three implementation
questions are resolved here rather than left to the coder to guess. Read this
before the rest.

1. **The bead's second bullet ("actor or target not a Player in the phase's
   game") is split into two numbered rules (2 and 3 below), one per field.**
   The spec-author brief requires splitting a rule that needs an "and"
   between two different outcomes, and here the outcome (which field the
   error lands on) differs by which side is wrong. A single implementation
   module may still check both in one pass (see Touches) — the split is for
   testability, not file layout.
2. **"The immediately preceding day phase of the same game" is defined as
   the day phase of that game with the largest `number` smaller than the
   current phase's `number`** (i.e. the nearest earlier day, not literally
   "yesterday" on a calendar). This coincides with "the previous calendar
   day" because `Game`'s state machine only ever alternates `:day` and
   `:night` (`transition :end_day, from: :day, to: :night` at
   `lib/werewolf_ash/games/game.ex:43` and
   `transition :end_night, from: :night, to: :day` at
   `lib/werewolf_ash/games/game.ex:44`) and `AdvancePhase` opens exactly
   one new `Phase` per transition with a monotonically incrementing `number`
   (`open_next_phase/4`'s `Games.create_phase(game.id, kind, (last_number ||
   0) + 1, ...)` at `lib/werewolf_ash/games/game/changes/advance_phase.ex:65`)
   — so two day phases of the same game are never adjacent in number and
   nothing inserts an extra day or night out of sequence. Concretely, "no
   earlier day phase exists" is the definition of "first day of the game,"
   and this is **not** the same as "this phase's `number` is 1": `start`'s
   `{AdvancePhase, to: :by_clock}` at `lib/werewolf_ash/games/game.ex:87`
   picks day or night depending on the game's clock at `now`, so a game can
   open at night, making its first *day* phase number 2. A rule-4 test must
   cover a game that opens at night to catch an implementation that
   hardcodes `number == 1` instead of "no earlier day phase in this game."
3. **The one existing test this bead breaks is fixed by changing which
   player it targets, not by loosening its assertion** — see "Existing
   tests this will break" below. The rule (target-alive) is correct as
   stated in the bead; the test's fixture data is what's stale.

## Goal

Creating an `Action` — a vote, a kill, an investigation, a protection, or (for
the fields this bead governs) a shot — now requires the action's target to be
a living player, and requires the actor and the target to both actually be
seated in the same game as the phase the action is filed against. The
bodyguard additionally cannot protect the player they protected on the
immediately preceding day. All three checks are enforced identically whether
the row is created through `:create` (vote/investigate/protect/shoot) or
through the pack's dedicated `:kill` action, and none of them can be worked
around by first attempting an action that gets rejected — a rejected action
never becomes a database row, so it never consumes anything a row-count-based
rule (the one-kill-per-phase limit) is counting.

## Rules

1. A `:vote`, `:kill`, `:investigate` or `:protect` action whose `target_id`
   names a player who is not currently alive is rejected with an error on
   field `:target_id`. This is unconditional on the `:kill` action (it is
   never anything else) and applies to `:create` only when `type` is one of
   those four — **not** `:shoot`: the bead defers the shot's target rules to
   `werewolf_ash-qss.7`, which has not yet defined the pending hunter's
   target constraints (see Out of scope).
2. An action whose `actor_id` does not name a `Player` seated in the same
   game as the phase named by `phase_id` is rejected with an error on field
   `:actor_id`. This includes an `actor_id` that does not resolve to any
   `Player` at all. Applies unconditionally to every type on `:create`
   (`:vote`, `:investigate`, `:protect`, `:shoot`) and to `:kill`.
3. An action whose `target_id` does not name a `Player` seated in the same
   game as the phase named by `phase_id` is rejected with an error on field
   `:target_id`. This includes a `target_id` that does not resolve to any
   `Player` at all. Same scope as rule 2: every `:create` type and `:kill`.
4. A `:protect` action is rejected with an error on field `:target_id` when
   its `target_id` equals the same actor's `:protect` target from the
   immediately preceding day phase of the same game (Assumption 2 defines
   "immediately preceding"). When no earlier day phase of that game exists —
   whether because this is the game's first phase or because the game's
   first phase was a night — the check has nothing to compare against and
   the action is allowed regardless of target. A different target on the
   very next day is allowed; the same target is allowed again once at least
   one day has passed where a different target (or no `:protect` at all) was
   recorded, because only the *immediately preceding* day is compared, not
   the actor's whole history.
5. (withdrawn as a standalone rule — it can't be broken on its own, because it follows from
   rule 1 on `:kill` plus the `one_kill_per_phase` identity. It is pinned instead by the
   rule 1 consequence test in Acceptance, which keeps the framework citation.)

## Out of scope

- `:shoot`'s target-alive rule and any other shoot-specific target
  constraint. `werewolf_ash-qss.7` owns the pending-hunter mechanics
  (`ShootRequiresPendingHunter`'s own moduledoc already says a dedicated
  pointer, if one lands, is qss.7's to consume,
  `lib/werewolf_ash/games/action/validations/shoot_requires_pending_hunter.ex:9-11`);
  this bead does not add a target-alive check for `:shoot` and does not
  change `ShootRequiresPendingHunter`.
- Lynch resolution and the day's vote tally — `werewolf_ash-qss.5`. This bead
  only stops a vote from targeting a dead player; it does not compute or
  change how votes are counted.
- Win-condition checking after a kill, and the kill's hand-off to the hunter
  — `werewolf_ash-qss.6`. That bead also touches the `:kill` action; see
  Touches for the overlap. This bead does not add a win check or a hunter
  hand-off.
- Owner-configurable role distribution, player bounds, or optional specials —
  `werewolf_ash-qss.14`. Nothing here depends on or changes how roles are
  dealt.
- Any new `Action` type, GraphQL mutation, or `Ash.Policy` authorization rule.
  The bead adds no action; no resource in this domain has a `policies do`
  block today (confirmed: `grep -rln "policies do" lib/werewolf_ash/games/*.ex
  lib/werewolf_ash/games/**/*.ex` matches nothing under `games/`), so there is
  no access-control layer for this bead to interact with. The new validation
  modules load `Player`/`Phase` with `authorize?: false`, matching the
  existing convention stated in `ActorAlive`'s and
  `TypeRequiresPhaseAndRole`'s own moduledocs
  (`lib/werewolf_ash/games/action/validations/actor_alive.ex:9-11`,
  `.../type_requires_phase_and_role.ex:13-15`) — this is a design-consistency
  choice verified by reading the new modules, not by a test, since no policy
  exists yet to make `authorize?: true` vs `false` observably different.
- `werewolf_ash-qss.20`'s own two assertion rewrites in
  `test/werewolf_ash/games/action_test.exs` (the `"a second kill for the same
  phase always fails (rule 11)"` test at lines 254-271, and `started_game/0`
  at lines 18-29). That bead is being spec'd in parallel against the same
  file at different lines than the one fix this bead requires (see "Existing
  tests this will break"); do not apply qss.20's changes here, and do not
  fold this bead's one-line fix into qss.20's scope either. Whichever of the
  two beads merges second will need a routine rebase over the same file —
  that is the reviewer's job, not a reason to widen either bead.

## Acceptance

- New validation covering rule 1 (name advisory, e.g.
  `WerewolfAsh.Games.Action.Validations.TargetAlive.validate/3`) — direct
  unit tests: `:ok` for a living target; an error on field `:target_id` for
  a dead one; `:ok` when `target_id` itself is absent (mirrors
  `ActorAlive`'s own nil-passthrough,
  `lib/werewolf_ash/games/action/validations/actor_alive.ex:21-23`, so a
  missing required attribute is still reported by the action itself, not
  this validation).
- New validation(s) covering rules 2 and 3 (advisory, e.g.
  `WerewolfAsh.Games.Action.Validations.ActorAndTargetInGame.validate/3`, or
  two separate modules — the split in the Rules section is about the test
  matrix, not the file count) — direct unit tests: `:ok` when actor, target
  and phase all share one game; an error on field `:actor_id` when the actor
  belongs to a different game than the phase; an error on field `:target_id`
  when the target does (two separate test cases, one per field, each
  changing only the one thing under test); `:ok` when `actor_id`/`target_id`/
  `phase_id` is absent (deferred to the action's own required-input check,
  same convention as the other validations here).
- New validation covering rule 4 (advisory, e.g.
  `WerewolfAsh.Games.Action.Validations.NoConsecutiveProtect.validate/3`) —
  direct unit tests: `:ok` for a `:protect` on a game's first-ever phase
  regardless of target (no earlier day phase exists at all); `:ok` for a
  `:protect` whose target differs from the actor's immediately preceding
  day's `:protect` target; an error on field `:target_id` when the target
  matches that immediately preceding day's target; `:ok` again for that same
  target one further day on, after an intervening day recorded a different
  target (Assumption 2's "gap" case) — and, per Assumption 2, a case where
  the game's very first phase is a night, confirming its first day phase is
  still treated as having no preceding day (not rejected by an
  implementation that assumes phase number 1 is always the first day).
- `WerewolfAsh.Games.create_action/4,5` — end-to-end rejection tests, one
  per rule that applies to `:create`: a dead target for `:vote`,
  `:investigate` and `:protect` (rule 1; a `:shoot` at a dead target is
  explicitly *not* covered here, since rule 1 excludes it); a cross-game
  actor and a cross-game target, each for at least one `:create` type
  (rules 2 and 3); the consecutive-protect rejection and its positive
  counterpart (rule 4). Each asserts on the error's `field`, not on message
  text, per the bead's own acceptance line.
- `WerewolfAsh.Games.create_kill_action/3,4` — end-to-end rejection tests:
  a dead target (rule 1); a cross-game actor and a cross-game target (rules
  2 and 3); and the rule 1 consequence test in the next bullet.
- Rule 1 consequence on `:kill` (formerly rule 5): a `create_kill_action` call naming a dead
  target is refused, and a second `create_kill_action` in the same phase naming a living
  target then succeeds, proving the refused attempt did not use up the phase's one kill.
  Break rule 1 on `:kill` in a scratch copy: the dead-target kill is inserted, and the living
  second kill then fails on `one_kill_per_phase`, so this test fails.
  Framework citation: validations declared on an action run while building
  the changeset in `Ash.Changeset.for_create/4`, before the data layer is
  ever touched (`deps/ash/lib/ash/changeset/changeset.ex:2017-2026`, "Run
  action changes & validations" / "Run validations..."). The data-layer
  insert itself is gated on `changeset.valid?` — `deps/ash/lib/ash/actions/
  create/create.ex:372`, `if changeset.valid? do` wraps every path that
  reaches the data layer inside `commit/3`. Since rule 1 is an ordinary
  `Ash.Resource.Validation` (the same mechanism as the already-merged
  `ActorAlive`, which is wired the identical way on `:kill` at
  `lib/werewolf_ash/games/action.ex:81`), a dead-target kill attempt makes
  `changeset.valid?` false during that pre-commit step and `commit/3` never
  calls the data layer — no row is written, so the `one_kill_per_phase`
  partial unique index (which only ever sees committed rows) is never
  consulted for that attempt.
- Cross-game actor fixtures (rule 2): build the cross-game actor as a real `Player` seated
  in a different game, never as an `actor_id` matching no player. `ActorAlive`
  (`lib/werewolf_ash/games/action/validations/actor_alive.ex:28`) already reports a missing
  actor on `:actor_id`, so a nonexistent id would produce two errors and break each test's
  single-error assertion for the wrong reason.
- End to end: one `Games.create_action` path through the domain code
  interface exercising rule 4's full arc in a single scenario — a bodyguard
  protects player X on day one; protecting X again on day two is rejected
  (field `:target_id`); protecting a different player Y on day two succeeds;
  protecting X again on day three succeeds (the gap case).

### Existing tests this will break

Grep for every call site of the two actions this bead validates:

```
grep -rn "create_action\|create_kill_action" lib/ test/ --include="*.ex" --include="*.exs"
```

This matches only `lib/werewolf_ash/games.ex:46-47` (the code interface
definitions) and three test files:
`test/werewolf_ash/games_test.exs`,
`test/werewolf_ash/games/action_test.exs`, and
`test/werewolf_ash/games/action/changes/apply_kill_test.exs:49`.

Checking each call site's actor/target against the game they belong to and
against `alive`, only one is affected — the rest use players that are alive
and in the same game as the phase (rules 2, 3 and 5 introduce no new
cross-game or dead-target combination anywhere else in the suite):

- **`test/werewolf_ash/games/action_test.exs:107-108` is stale and must be
  fixed by this bead.** The test `"rejects a dead actor's vote, investigation
  or protection (rule 1)"` sets three players dead
  (`Games.update_player!(p.villager, %{alive: false})` at line 97,
  `p.seer` at line 98, `p.bodyguard` at line 99) and then asserts, at line
  107, `assert {:error, %Ash.Error.Invalid{errors: [%{field: :actor_id}]}} =`
  against the call at line 108,
  `Games.create_action(day.id, p.bodyguard.id, p.villager.id, :protect)`.
  That call's actor (`p.bodyguard`) *and* target (`p.villager`) are both
  dead. Once this bead's rule 1 is wired onto `:protect`, that single call
  produces two errors — the existing `ActorAlive` failure on `:actor_id`
  *and* the new target-alive failure on `:target_id` — and the exact
  one-element list pattern `[%{field: :actor_id}]` no longer matches a
  two-element error list, so this assertion fails.

  The rule is correct; the test's fixture is what's stale — it happened to
  reuse an already-dead player (`p.villager`) as this sub-case's target
  where the sibling assertions two lines above it (lines 101-102 and
  104-105) both target the still-alive `p.werewolf`. Fix: change line 108's
  target from `p.villager.id` to `p.werewolf.id`, matching the pattern
  already used by the other two assertions in the same test, so this
  sub-case isolates the actor-dead condition exactly as its neighbors do and
  the existing single-error assertion keeps its meaning. Do not loosen the
  assertion itself — the one-element match stays; only the fixture target
  changes.

- Every other call site keeps its target alive and its actor and target in
  the same game as the phase used, so none of rules 1-4 changes their
  outcome:
  - `test/werewolf_ash/games_test.exs`'s `"actions"` describe block
    (lines 542-597, calls at 550/570/573/579/583/588/592) uses only `alice`
    and `bob`, seated together in the one `game` built in that block's
    `setup` (lines 543-546) and never marked dead.
  - `test/werewolf_ash/games/action_test.exs`'s other calls all draw actor
    and target from the single `players` map `started_game/0` returns
    (lines 18-29), seated in the one game that helper builds, and the only
    players ever marked dead in this file are: `p.hunter` (lines 80, 345,
    always targeted with, or targeting, a still-living player), `p.villager`/
    `p.seer`/`p.bodyguard` (lines 97-99, addressed above), and `p.werewolf`
    (line 233, whose only later use as an actor at line 236 targets the
    still-alive `p.villager`).
  - `test/werewolf_ash/games/action/changes/apply_kill_test.exs:49` seats
    `bodyguard` and `target` in the same freshly generated `game` (lines
    42-47) and marks neither dead.

## Touches

Advisory only; the coder may deviate, including on whether rules 2 and 3
share one module.

- `lib/werewolf_ash/games/action.ex` — wire the new validations into
  `:create` (rule 1 scoped to `[:vote, :investigate, :protect]` like
  `ActorAlive`'s own `where:`; rule 4 scoped to `:protect` like the existing
  bodyguard self-target check; rules 2/3 unconditional) and into `:kill`
  (rules 1, 2, 3 unconditional, alongside the existing unconditional
  `ActorAlive`/`TypeRequiresPhaseAndRole` calls there). Overlap: werewolf_ash-qss.6
  also edits the `:kill` action, adding a win-check change after `ApplyKill`.
  Whichever of the two lands second must rebase onto the other's `:kill` block
  and keep both the validations and the change.
- `lib/werewolf_ash/games/action/validations/` — new module(s) for rules 1,
  2/3, and 4, following the existing `ActorAlive`/`TypeRequiresPhaseAndRole`/
  `ShootRequiresPendingHunter` style (a `use Ash.Resource.Validation` module,
  `Games.get_player`/`Games.get_phase` with `authorize?: false`, nil
  attributes pass through as `:ok`).
- `test/werewolf_ash/games/action/validations/` — new direct unit test
  file(s) mirroring the new module(s).
- `test/werewolf_ash/games/action_test.exs` — the one-line fixture fix above,
  plus new end-to-end cases for rules 1-4 and the rule 1 consequence test (see Acceptance). Expect this file
  to also be touched by the separate `werewolf_ash-qss.20` bead at different
  lines (see Out of scope).
- No `mix ash.codegen` migration is expected — this bead adds validations,
  not attributes, relationships, or identities.
