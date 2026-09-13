# werewolf_ash-qss.6: Night: kill aftermath (win check) and transition to day

Depends on: none

## For the owner

**What changes.** When a werewolf's kill lands, the game immediately checks whether that death brings the werewolves to parity with everyone else. If so, the game ends right then, in the middle of the night — nobody has to wait for morning. If the kill was blocked (a protected target) or doesn't finish things, the night keeps going, and the next day starts with nothing left over to resolve.

**Decisions.**
1. A hunter killed at night — a plain death now, or their revenge shot fires right away? **Decided:** plain death for now; the shot (qss.7) is a follow-up bead landing right after this one.
2. Anything announced when a kill finishes the game mid-night? **Decided:** no — announcements (qss.19) are a separate bead; this one only changes game state.
3. Night ends with no kill (wolves didn't act, or the kill was blocked)? **Decided:** nothing to resolve; day starts as normal.
4. Should the scheduler try to force a dawn transition on a game that already finished mid-night? **Decided:** no — a finished game is left alone; that requirement is recorded on the scheduler bead (qss.9), not built here.

**Rule changes.** Extends the settled rule on the wolf kill ("...the victim dies immediately unless the bodyguard protected them that day, in which case the kill is spent and they survive"): a kill that lands is followed at once by a win check; if it brings the wolves to parity, the game ends immediately, mid-night, without waiting for the night to end. A spent (protected) kill runs no win check at all.

## Goal

Once a werewolf's kill has landed (qss.4's `:kill` action already applies it
immediately), the game reacts to it without waiting for dawn: a kill that
brings the wolves to parity ends the game that same night, and a spent
(protected) kill changes nothing. `end_night` then does exactly one thing —
move the game from night to day — because there is no kill left for it to
resolve.

**Resolving a conflict in the bead's own text:** the bead's `Done:` line says
"a hunter killed at night triggers the hand-off," but the bead's own `NOTES`
(recorded the same day, 2026-09-12) say "land WITHOUT hunter hand-off (a dead
hunter is a plain death here); qss.7 adds the hunter hand-off to this reactor
afterwards," and the epic's own dependency graph has qss.7 depend on qss.6
(not the reverse). The `NOTES` win: this spec builds no hunter hand-off. A
hunter killed at night is a plain death, identical in every observable way to
any other role's death, until qss.7 lands (rule 5).

## Rules

1. A `:kill` action that lands (`result: %{"killed" => true}` — the
   unprotected branch of `WerewolfAsh.Games.Action.Changes.ApplyKill`,
   `lib/werewolf_ash/games/action/changes/apply_kill.ex:32-41`) runs an
   immediate win check: `WerewolfAsh.Games.Reactors.ResolveWin` (qss.8) is
   composed against a freshly loaded `WerewolfAsh.Games.Game` for that kill's
   game, synchronously, before `Games.create_kill_action`/
   `create_kill_action!` returns. This composition is a separate step from
   `ApplyKill`'s own `after_action` hook — `ApplyKill.change/3` itself is not
   modified. (See "Existing tests this will break" for why that boundary
   matters and is not optional.)

   **The `Reactor.run/4` call composing `ResolveWin` must pass `async?:
   false` in its `options` (the 4th positional argument — `Reactor.run(reactor,
   inputs \\ %{}, context \\ %{}, options \\ [])`, `deps/reactor/lib/reactor.ex:212`,
   validated against `@run_schema`, `deps/reactor/lib/reactor.ex:152`, whose
   `async?` entry defaults to `true`, `deps/reactor/lib/reactor.ex:170-174`).**
   Left at that default, `ResolveWin`'s `read :living_players` step (composed
   from `CheckWin`) runs inside a task started by
   `Task.Supervisor.async_nolink/4`
   (`deps/reactor/lib/reactor/executor/async.ex:73`) — a different process
   from the one running the kill's own `after_action` hook. The kill's
   `Player` and `Action` updates run inside the `:kill` action's own create
   transaction (`deps/ash/lib/ash/actions/create/create.ex:547` wraps the
   changeset's changes in `transaction?: Keyword.get(opts, :transaction?,
   true) && changeset.action.transaction?`, true by default here). In
   production that separate task checks out a different pool connection and,
   being outside the still-open transaction, cannot see the victim's
   uncommitted `alive: false` — it would count the victim as still alive, so
   a kill that reaches wolf parity would wrongly decide `:continue` instead
   of finishing the game. **No test in this bead's suite can catch a missing
   `async?: false`**: `DBConnection`'s ownership pool resolves a checkout
   through the calling process's `$callers` list, which "is set by default
   for tasks from Elixir v1.8"
   (`deps/db_connection/lib/db_connection/ownership.ex:55-64`), so under
   `mix test`'s Ecto sandbox a spawned task still finds the test's checked-out
   connection and the async and synchronous paths behave identically; the
   two diverge only in production, where there is no sandbox and no
   `$callers` fallback across pool connections. The code-reviewer must verify
   this rule by reading the call site, not by running the suite.

   If `ResolveWin` returns `{:error, _}`, the composing hook must return that error rather than
   swallowing it, so the whole `:kill` transaction rolls back and no half-applied kill is left behind
   (a dead victim with no win decision).
2. A `:kill` action whose kill is spent (`result: %{"killed" => false}`, the
   protected-target branch) runs no win check at all: the game's `state` and
   `winner` are exactly what they were immediately before the kill, even when
   the living counts going in already sit at exact wolf parity (i.e. this is
   not merely "the outcome happens not to change" — the check must not run).
3. When rule 1's win check decides `:wolves_wins` or `:village_wins`, the
   game's `state` becomes `:finished` and `winner` is set to `:wolves` or
   `:village` respectively, mid-night, without waiting for `end_night`. This
   is `ResolveWin`'s own `finish` step (`lib/werewolf_ash/games/reactors/resolve_win.ex:48-58`)
   acting on `Game`'s existing `finish` action
   (`lib/werewolf_ash/games/game.ex:116-122`) — this bead adds no second
   implementation of the decision or the transition.
4. When rule 1's win check decides `:continue`, the game's `state` stays
   `:night` and `winner` stays `nil`; the night carries on exactly as before
   this bead (further actions of other types may still be created, subject to
   the existing one-per-actor-per-phase-per-type identity and the
   `one_kill_per_phase` identity that already blocks a second kill in the
   same phase).
5. A landed kill on a player whose role is `:hunter` is, for this bead, a
   plain death: `alive` is set to `false` by the existing `ApplyKill`
   behaviour and rule 1's win check runs exactly as it would for any other
   role. No `hunter_pending` entry, no deferred transition, no other
   hunter-specific branching is added. (This is the seam qss.7 will use —
   see "Out of scope.")
6. `end_night` transitions the game's `state` from `:night` to `:day` (and
   opens the next phase, via the existing `AdvancePhase` change,
   `lib/werewolf_ash/games/game/changes/advance_phase.ex`) without
   re-resolving, re-applying, or re-checking any kill from the closing night:
   a kill that already landed, or was already spent, during that night is
   untouched by calling `end_night` — the target's `alive` value and the
   `Action` row's `result` do not change, and no new `Action` row is created
   by the transition. (`end_night`'s current implementation,
   `lib/werewolf_ash/games/game.ex:103-114`, already has no kill-resolution
   code path; this rule locks that down against regression rather than
   changing it.)
7. (withdrawn — not independently testable; its statement is not a behaviour
   of the system but a constraint on the implementation, and no test can
   fail solely because it was violated without also failing rule 1, 3 or 4.
   Moved to "Out of scope.")
8. The seer's `:investigate` result
   (`WerewolfAsh.Games.Action.Changes.RecordInvestigationResult`, qss.4) is
   unaffected by anything in this bead: a night containing both an
   `:investigate` and a `:kill` still returns the correct
   `result: %{"is_werewolf" => ...}` for the investigation, unchanged by the
   kill's aftermath or the win check running in the same phase. This bead
   reads that result in its own end-to-end test but writes no code that
   touches it.

## Out of scope

- **Hunter hand-off itself** (qss.7): entering `hunter_pending`, the 1h
  window, `shoot`, and the random fallback. Rule 5 only pins that a dead
  hunter is a plain death *for now*; do not add a check for the victim's role
  anywhere in this bead's code, not even as a no-op branch or a comment-only
  stub — the seam is "immediately after a landed kill, before/around the win
  check," and qss.7 will insert its own check there. Leaving no branch at all
  is the correct shape, not an oversight.
- **`EndDay` / lynch resolution** (qss.5): do not touch `end_day`, and do not
  refactor `CheckWin`/`ResolveWin` into something "shared" between day and
  night beyond both beads independently calling the same existing module.
  qss.5 composes its own win check at its own point in the day's resolution.
- **Action target/actor validity** (qss.18): no new validation on `:target_id`
  liveness, no cross-game actor/target/phase check, no consecutive-protect
  rule. Note for the pipeline: qss.18 and this bead both touch
  `lib/werewolf_ash/games/action.ex`'s `:kill` action block
  (`action.ex:73-86`) — qss.18 adds a `validate`, this bead adds a `change`.
  They are additive and independent at the code level, but were written as
  parallel specs; if both land as separate PRs expect a rebase, not a design
  conflict.
- **Configurable setup** (qss.14): role distribution, werewolf count, optional
  specials, min/max players are all untouched. Tests here may use whatever
  fixed player counts are convenient (as `apply_kill_test.exs` and
  `resolve_win_test.exs` already do), not the qss.3/qss.14 minimum-5 lobby
  flow, when a test needs precise living counts rather than a full lobby
  start.
- **Dawn/dusk announcements and death-triggered role visibility** (qss.19):
  this bead sends no chat message and writes no feed event when a kill lands,
  when the win check decides, or when `end_night` runs. It only changes
  `Game`, `Action` and `Player` rows.
- **Full role reveal at game over** (qss.17): out; `finish` already sets
  `winner` and this bead does not add anything to what becomes visible when a
  game ends.
- **The scheduler** (qss.9): `end_night` keeps taking an explicit `now`
  argument and is only ever invoked by a caller (a test today, the scheduler
  later); this bead adds no clock-driven trigger.
- **Restricting who a werewolf may target with `:kill`** (e.g. forbidding a
  wolf from targeting a fellow werewolf): no rule anywhere asks for this: the
  current absence of such a restriction is unchanged. Do not add it while
  wiring the win check, even though a self-targeting wolf kill is the only
  way a `:kill` could ever produce `:village_wins`.
- **Cleaning up after a mid-night finish**: when rule 1's win check finishes the game during a
  night, the night phase stays open and `phase_ends_at` stays set. `end_night` on a finished game
  returns `NoMatchingTransition` and writes nothing (`test/werewolf_ash/games_test.exs:297-306`).
  This bead leaves that as is. The scheduler (werewolf_ash-qss.9) must act only on games in `:day`
  or `:night`, and that requirement is recorded on its bead.
- **Modifying `ApplyKill`** (`lib/werewolf_ash/games/action/changes/apply_kill.ex`):
  its `change/3` and the shape of `result` it writes are unchanged. The win
  check is new, separate code; see rule 1 and "Existing tests this will
  break."
- **A second implementation of the win decision or the finish transition**
  (was rule 1's rule 7, withdrawn as untestable on its own): this bead adds
  no reimplementation, wrapper, or fork of the win decision or the finish
  transition — the only new call site anywhere in this bead is the single
  composition of `WerewolfAsh.Games.Reactors.ResolveWin` described in rules
  1, 3 and 4. If the coder finds themselves writing a second `decide`/`finish`
  path (e.g. a special case for the mid-night kill outcome versus qss.5's own
  end-of-day one), that duplication belongs nowhere in this codebase — both
  beads call the same existing `ResolveWin`/`CheckWin` modules independently
  from their own resolution points.

## Acceptance

- `WerewolfAsh.Games.create_kill_action/3,4` (and `create_kill_action!/3,4`)
  — extend the existing `"create_kill_action/3,4"` describe block
  (`test/werewolf_ash/games/action_test.exs:205`) with:
  - a landed kill that brings wolves to parity finishes the game (`state:
    :finished`, `winner` matching the reactor's decision) by the time the
    call returns (rules 1, 3);
  - a landed kill that does not reach parity leaves `state: :night`,
    `winner: nil` (rule 4);
  - a landed, non-decisive kill on the dealt hunter is a plain death: that hunter is `alive: false`,
    the game stays `state: :night`, and nothing enters `hunter_pending` (rule 5);
  - a spent (protected) kill runs no win check even when the living counts
    are already at exact wolf parity going in — construct the parity
    directly via `Games.update_player!` before the kill (the same technique
    `resolve_win_test.exs` already uses to reach precise counts,
    `test/werewolf_ash/games/reactors/resolve_win_test.exs:56-69`), so that a
    check-runs-regardless-of-spent implementation would visibly finish the
    game here and a correct one would not (rule 2).
- The module implementing the win-check composition (name advisory — e.g. a
  new `Ash.Resource.Change` registered as a second `change` in the `:kill`
  action, ordered after `ApplyKill`, per rule 1) — direct unit tests on its
  own contract, mirroring `apply_kill_test.exs`'s pattern of staging a
  `Ash.Seed.seed!`'d action and invoking the hook directly
  (`test/werewolf_ash/games/action/changes/apply_kill_test.exs:12-25`): given
  a landed kill (`result: %{"killed" => true}`) and living counts that decide
  `:continue`, `:village_wins` and `:wolves_wins` respectively, the game ends
  up in the matching state; given a spent kill (`result: %{"killed" =>
  false}`), the game is untouched regardless of the living counts, and the hook returns `{:ok, _}`.
  Build these games in `:night`, not the `:lobby` games `apply_kill_test.exs` uses: from `:lobby`,
  `finish` isn't allowed, so a win check that wrongly ran on a spent kill would still leave the
  game untouched and the test would pass for the wrong reason. Separately, use exactly that
  `:lobby` case to pin rule 1's error path: a decisive landed kill on a `:lobby` game makes
  `ResolveWin` fail, and the hook must return `{:error, _}`.
- `WerewolfAsh.Games.end_night/1,2,3` (and `end_night!/1,2,3`) — a direct
  test that a night containing a landed, non-decisive kill transitions
  cleanly to `:day` with the killed player still `alive: false`, no new
  `Action` row created by the transition, and the game's total count of
  `type: :kill` actions unchanged by it (rule 6).
- End to end: one path through the domain code interface, extending the
  style of the existing `"end to end"` describe block
  (`test/werewolf_ash/games/action_test.exs:292-354`): start a game, day one
  the bodyguard protects a target, `end_day`, night one a werewolf's kill
  lands on a different (non-decisive) target while the seer investigates in
  the same phase — assert the seer's `result` is correct and unaffected
  (rule 8) — then `end_night` — assert the game is now in a fresh `:day`
  phase, the killed player is still dead, and nothing about the investigation
  or the protection changed (rules 1, 4, 6, 8 together in one walk).

### Existing tests this will break

Grep for every call site this bead's rules could touch:

```
grep -rn "create_kill_action\|end_night\|ApplyKill\|ResolveWin\|CheckWin" lib/ test/ --include="*.ex" --include="*.exs"
```

Hits, by file:

- `lib/werewolf_ash/games.ex:25,47` — the code interface definitions
  (`end_night`, `create_kill_action`).
- `lib/werewolf_ash/games/action.ex:18,85` — `ApplyKill`'s alias and its
  `change` in the `:kill` action.
- `lib/werewolf_ash/games/game.ex:11,44,103` — the moduledoc mention and the
  `end_night` transition/action.
- `lib/werewolf_ash/games/reactors/resolve_win.ex` and `check_win.ex` — the
  modules themselves (qss.8, unchanged by this bead).
- `lib/werewolf_ash/games/action/changes/apply_kill.ex:1` — the module
  itself.
- `test/werewolf_ash/games_test.exs:184,214,297,306` — `end_night!`/
  `end_night` calls in the "phase transitions" describe block.
- `test/werewolf_ash/games/reactors/check_win_test.exs` and
  `resolve_win_test.exs` — qss.8's own tests, calling the reactors directly,
  never through `create_kill_action`.
- `test/werewolf_ash/games/action_test.exs:191,205,215,228,231,236,248,
  259,263,266,278,307,316,319,336` — every `end_night!`/`create_kill_action`
  call in that file.
- `test/werewolf_ash/games/action/changes/apply_kill_test.exs:1,10,21` —
  the module alias and the direct `ApplyKill.change/3` invocation.

**No currently-passing assertion's expected value changes under rules 1-8 as
specified.** Every `create_kill_action`/`create_kill_action!` call in
`action_test.exs` is made against `started_game/0`'s fixture
(`test/werewolf_ash/games/action_test.exs:18-29`): 5 players dealt 1
werewolf, 1 seer, 1 bodyguard, 1 hunter, 1 villager (qss.3's
`max(1, div(5,4)) = 1` werewolf formula). Every kill test there kills exactly
one target once, taking non-wolves from 4 to 3 — `CheckWin.decide/1`
(`lib/werewolf_ash/games/reactors/check_win.ex:83`) requires
`wolves >= non_wolves` for a wolf win, and `1 >= 3` is false, so rule 1's win
check would decide `:continue` in every one of them: `state` stays `:night`
(the state these tests already run in), which is what they already assume
implicitly (none of them assert on `.state`, confirmed by
`grep -n "\.state ==" test/werewolf_ash/games/action_test.exs
test/werewolf_ash/games/action/changes/apply_kill_test.exs`, which returns no
hits). The `end_night!` calls in both `games_test.exs` and `action_test.exs`
never occur in the same test as a kill action, so rule 6 changes nothing
about their existing assertions either — none of them assert about `Action`
rows.

**The one implementation path that *would* break existing tests: folding
rule 1's win check into `ApplyKill.change/3` itself, instead of adding it as
a separate step (rule 1's explicit boundary).** `apply_kill_test.exs`'s
`stage/3` helper (`apply_kill_test.exs:12-25`) calls `ApplyKill.change(...)`
directly and invokes its lone `after_action` hook by hand, bypassing the
`:kill` action's other validations and changes entirely. Its games are built
with `generate(game())` alone (`apply_kill_test.exs:29` and `:58`), which
never calls `start`, so `state` defaults to `:lobby`
(`lib/werewolf_ash/games/game.ex:174`). Both of those tests
(`"an unprotected target dies and the row records it"`,
`apply_kill_test.exs:28-39`, and `"a kill on a game's first-ever phase
behaves like the unprotected case"`, `apply_kill_test.exs:57-67`) leave only
the werewolf alive after the kill lands (1 werewolf, 1 villager target, no
other players) — `CheckWin.decide(%{wolves: 1, non_wolves: 0})` is
`:wolves_wins` (`1 >= 0`). If the win check ran from inside `ApplyKill`'s own
hook, it would try to run `Game`'s `finish` transition
(`transition :finish, from: [:day, :night, :hunter_pending], to: :finished`,
`lib/werewolf_ash/games/game.ex:45`) on a game whose `state` is `:lobby` —
not a matching source state — so `Reactor.run` would return `{:error, ...}`
instead of the `{:ok, updated}` both tests assert at lines 35 and 63,
breaking both. The fix is not to loosen those assertions (they are correct
unit tests of `ApplyKill`'s own narrow contract); it is to keep the win
check out of `ApplyKill` entirely, exactly as rule 1 and "Out of scope"
require.

## Touches

Advisory only.

- `lib/werewolf_ash/games/action.ex` — the `:kill` action block (lines
  73-86), to add the new `change` after `ApplyKill`.
- A new module under `lib/werewolf_ash/games/action/changes/`, or wherever
  the coder judges the win-check composition belongs, implementing rules 1-5.
- `lib/werewolf_ash/games/reactors/resolve_win.ex` — read-only; its own
  moduledoc already warns that a stale `game` struct passed in would carry
  stale state into the `finish` transition (`resolve_win.ex:13-15`), which is
  why the composed `game` must be loaded fresh (e.g. via the kill's
  `phase_id` → `Phase.game_id` → `Games.get_game!/1,2`) rather than reused
  from anywhere earlier in the request.
- `async?: false` is a hard requirement, not advisory — see rule 1. It also
  happens to match the only two existing call sites of these reactors,
  `check_win_test.exs:10` and `resolve_win_test.exs:9`.
- `test/werewolf_ash/games/action_test.exs` — new cases in the
  `"create_kill_action/3,4"` and `"end to end"` describe blocks.
- A new test file alongside `apply_kill_test.exs` for the win-check
  composition module's own direct unit tests.
- `test/werewolf_ash/games_test.exs` — a possible new case in "phase
  transitions" for rule 6, though `action_test.exs` may be the more natural
  home since it already has kill fixtures.
- The precedent for chaining two independently-hooked `Ash.Resource.Change`
  modules inside one action already exists in this codebase: `Game`'s
  `:start` action runs `change DealRoles` then
  `change {AdvancePhase, to: :by_clock}` (`lib/werewolf_ash/games/game.ex:86-87`),
  each registering its own `after_action` hook
  (`deal_roles.ex:21`, `advance_phase.ex:43-45`). The new `:kill`-action
  change can follow the same shape.
