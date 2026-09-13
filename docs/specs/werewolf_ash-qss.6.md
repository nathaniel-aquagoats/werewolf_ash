# werewolf_ash-qss.6: Night: kill aftermath (win check) and transition to day

Depends on: none

## For the owner

**What changes.** When a werewolf's kill lands, the game immediately checks whether that death brings the werewolves to parity with everyone else. If so, the game ends right then, in the middle of the night — nobody has to wait for morning. If the kill was blocked (a protected target) or doesn't finish things, the night keeps going. When morning comes, the game checks one more time before opening a new day — this catches a win that was already true going into the night but nothing had checked yet (for example, a game whose starting numbers already favoured the wolves) — and if a winner is found there, that dawn ends with no day starting at all.

**Decisions.**
1. A hunter killed at night — a plain death now, or their revenge shot fires right away? **Decided:** plain death for now; the shot (qss.7) is a follow-up bead landing right after this one.
2. Anything announced when a kill finishes the game mid-night? **Decided:** no — announcements (qss.19) are a separate bead; this one only changes game state.
3. Night ends with no kill (wolves didn't act, or the kill was blocked)? **Decided:** nothing to resolve; day starts as normal, unless dawn's own check (decision 6) finds the game already won some other way.
4. Should the scheduler try to force a dawn transition on a game that already finished mid-night? **Decided:** no — a finished game is left alone; that requirement is recorded on the scheduler bead (qss.9), not built here.
5. When does the game end after a winning night kill? **Decided:** in the same instant as the kill.
6. Does dawn also check for a win? **Decided:** yes; a won game finishes instead of starting a day, with no day phase left.

**Rule changes.** Extends the settled rule on the wolf kill ("...the victim dies immediately unless the bodyguard protected them that day, in which case the kill is spent and they survive"): a kill that lands is followed at once, in the same instant, by a win check; if it brings the wolves to parity, the game ends immediately, mid-night, without waiting for the night to end. A spent (protected) kill runs no win check at all. Dawn's own transition (`end_night`) runs the same win check itself, one more time, before opening a new day; if it finds a winner, the game finishes there instead, and no day phase is left for it.

## Goal

Once a werewolf's kill has landed (qss.4's `:kill` action already applies it
immediately), the game reacts to it without waiting for dawn: a kill that
brings the wolves to parity ends the game that same night, and a spent
(protected) kill changes nothing. `end_night` moves the game from night to
day, and also checks the same win condition itself, one more time, before
doing so — not to resolve any kill (there is none left for it to resolve),
but as a checkpoint: a win that was already true when the night began, from
before any kill this bead's win check would have caught, is never carried
past dawn undetected.

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
   by the transition. (`end_night`'s previous implementation had no
   kill-resolution code path; this rule locks that down against regression
   rather than changing it.) This is distinct from — and does not conflict
   with — rules 9-11 below, which are about `end_night` also checking
   whether the *game overall* has been won, not about resolving any
   individual kill.
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
9. `end_night` gains a second `change`, appended after `{AdvancePhase, to:
   :day}` in `:end_night`'s own `change` list (the same chaining precedent
   `:start` already uses for `DealRoles` then `AdvancePhase`,
   `lib/werewolf_ash/games/game.ex:86-87`, each change registering its own
   `after_action` hook). This new change's hook composes
   `WerewolfAsh.Games.Reactors.ResolveWin` — `Reactor.run(ResolveWin,
   %{game: <the day-transitioned game AdvancePhase's own hook already
   produced and returned>}, %{}, async?: false)` — exactly once per
   `end_night` call, synchronously, in the same transaction as the
   transition itself, for the same reason and by the same mechanism rule 1
   already establishes for the kill's own composition (`Reactor.run/4`'s
   `async?` option defaulting to `true`, `deps/reactor/lib/reactor.ex:152,170-174`;
   `end_night`'s own `Player`/`Game`/`Phase` writes run inside the update
   action's own transaction, `deps/ash/lib/ash/actions/update/update.ex:681`,
   so an async composition here would race the same way rule 1 describes for
   the kill). This check exists for a case rule 1 cannot reach: a game can
   arrive at a night already at wolf parity without any kill of this bead's
   ever having run — `start` deals roles and opens the first phase but
   composes no win check of its own, so a game whose very first role deal
   already puts the wolves at parity would otherwise go unnoticed until
   someone acts. No test in this bead's own suite distinguishes `async?:
   false` from a bug that removes it here either, for the same reason given
   for rule 1; the code-reviewer verifies this one by reading the call site
   too.
10. If rule 9's check decides `:village_wins` or `:wolves_wins`, the game
    finishes (`state: :finished`, `winner` set — `ResolveWin`'s `finish` step
    transitions from `:day`, an allowed source state for `finish`,
    `lib/werewolf_ash/games/game.ex:45`) and this same change destroys — not
    merely closes — the day `Phase` row that `AdvancePhase`'s own hook
    already opened for this call (found via the game's `current_phase`
    relationship, `lib/werewolf_ash/games/game.ex:202-207`, which by this
    point in `end_night` is exactly that new day phase), mirroring
    `docs/specs/werewolf_ash-qss.5.md`'s rules 13-14 for the symmetric dusk
    case (read there for the approach; this bead does not depend on qss.5
    landing first or at all). The night `Phase` that `AdvancePhase` already
    closed (`ended_at` set) is untouched by this. Like qss.5's own rule 13
    for the symmetric dusk case: `finish`
    (`lib/werewolf_ash/games/game.ex:116-122`) only sets `winner` and
    transitions `state` — it does not clear `phase_ends_at`, so a game
    finished by this rule keeps whatever value `AdvancePhase` already
    computed for the day phase this same rule then destroys. This rule does
    not require, and no test should assert, that `phase_ends_at` is cleared
    or changed by finishing. Once `end_night` returns under this rule: no
    `Phase` row for that game has `ended_at: nil`, and no `Phase` row for
    that game has `kind: :day` with the `number` `AdvancePhase` assigned for
    this call.
11. If rule 9's check decides `:continue`, `end_night` leaves the game and
    its phases exactly as `AdvancePhase` already produced them (`state:
    :day`, the new day phase open, nothing destroyed) — every existing test
    of that path (`test/werewolf_ash/games_test.exs`'s "phase transitions"
    describe block; `test/werewolf_ash/games/action_test.exs:238-251`) keeps
    passing unmodified, because every one of them starts from
    `started_game()`/`ready()`'s fixture: 1 werewolf, 4 non-wolves, nobody
    killed — `CheckWin.decide(%{wolves: 1, non_wolves: 4})` is `:continue`
    (`1 < 4`, `lib/werewolf_ash/games/reactors/check_win.ex:83`).

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
  qss.5 composes its own win check at its own point in the day's resolution;
  this bead's `end_night` rules 9-11 are written to mirror qss.5's rules
  13-14 in *approach* without depending on qss.5's own code existing.
- **Action target/actor validity** (qss.18): already merged
  (`ad2c0ac`) — `TargetAlive`, `ActorAndTargetInGame` and
  `NoConsecutiveProtect` are already validating on `Action`'s `:create` and
  `:kill` actions (`lib/werewolf_ash/games/action.ex:54-60,99-102`). This
  bead adds no new validation of its own on `:target_id` liveness or
  cross-game actor/target/phase checks; it only adds the `change` described
  in rule 1, after the validations qss.18 already put in place.
- **Configurable setup** (qss.14): role distribution, werewolf count, optional
  specials, min/max players are all untouched. Tests here may use whatever
  fixed player counts are convenient (as `apply_kill_test.exs` and
  `resolve_win_test.exs` already do), not the qss.3/qss.14 minimum-5 lobby
  flow, when a test needs precise living counts rather than a full lobby
  start.
- **Dawn/dusk announcements and death-triggered role visibility** (qss.19):
  this bead sends no chat message and writes no feed event when a kill lands,
  when either win check decides, or when `end_night` runs. It only changes
  `Game`, `Phase` and `Player` rows.
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
  returns `NoMatchingTransition` and writes nothing (`test/werewolf_ash/games_test.exs:297-306`),
  so rule 9's dawn check is never reached for that game at all — `end_night` is never called on it
  in the first place once it's finished. This bead leaves that as is. The scheduler
  (werewolf_ash-qss.9) must act only on games in `:day` or `:night`, and that requirement is
  recorded on its bead.
- **Modifying `ApplyKill`** (`lib/werewolf_ash/games/action/changes/apply_kill.ex`):
  its `change/3` and the shape of `result` it writes are unchanged. The win
  check is new, separate code; see rule 1 and "Existing tests this will
  break."
- **Modifying `AdvancePhase`**
  (`lib/werewolf_ash/games/game/changes/advance_phase.ex`): its `change/3`,
  its clock computation, and its phase-opening/closing logic are unchanged.
  Rule 9's new logic is a separate `change` appended after it in
  `:end_night`'s list, exactly like rule 1's new change is separate from
  `ApplyKill`.
- **A second implementation of the win decision or the finish transition**
  (was rule 1's rule 7, withdrawn as untestable on its own): this bead adds
  no reimplementation, wrapper, or fork of the win decision or the finish
  transition — the only two call sites anywhere in this bead are the
  composition of `WerewolfAsh.Games.Reactors.ResolveWin` described in rules
  1, 3 and 4 (the kill's own check) and the one described in rules 9 and 10
  (dawn's check). If the coder finds themselves writing a second
  `decide`/`finish` path (e.g. a special case for the mid-night kill outcome
  versus qss.5's own end-of-day one, or a third path duplicating either of
  this bead's own two), that duplication belongs nowhere in this codebase —
  every caller, in every bead, calls the same existing
  `ResolveWin`/`CheckWin` modules independently from its own resolution
  point.

## Acceptance

- `WerewolfAsh.Games.create_kill_action/3,4` (and `create_kill_action!/3,4`)
  — extend the existing `"create_kill_action/3,4"` describe block
  (`test/werewolf_ash/games/action_test.exs:261`) with:
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
- The new `Ash.Resource.Change` appended to `:end_night` (rules 9-10, name
  advisory) — direct unit test(s) on its own contract, staged the way
  `apply_kill_test.exs:12-25`'s `stage/3` helper stages `ApplyKill` (build a
  bare changeset, run it through `AdvancePhase`'s own hook first so the new
  day `Phase` row genuinely exists, matching production order, then invoke
  this change's hook by hand): in a scenario that decides a winner, assert
  the day `Phase` row it just created no longer exists (`Games.get_phase/1`
  returns `{:error, %Ash.Error.Query.NotFound{}}` or equivalent) while the
  closed night phase is untouched; separately, in a scenario that decides no
  winner, assert the day phase from `AdvancePhase` is left exactly as
  `AdvancePhase` created it (rules 10, 11).
- `WerewolfAsh.Games.destroy_phase/1,2` — a direct unit test: create a
  `Phase`, destroy it through the domain, and assert `Games.get_phase/1` (or
  `get_phase!/1`) no longer finds it. This is a thin wrapper over `Phase`'s
  already-existing primary `:destroy` action
  (`lib/werewolf_ash/games/phase.ex:22`), exposed through the domain for the
  first time by this bead (see "Touches" for why `docs/specs/werewolf_ash-qss.5.md`
  may add the same `define` independently).
- `WerewolfAsh.Games.end_night/1,2,3` (and `end_night!/1,2,3`) — extend the
  existing "phase transitions"/`action_test.exs` coverage: a night containing
  a landed, non-decisive kill transitions cleanly to `:day` with the killed
  player still `alive: false`, no new `Action` row created by the
  transition, and the game's total count of `type: :kill` actions unchanged
  by it (rule 6); a night whose living counts, at the moment `end_night` is
  called, decide `:village_wins`/`:wolves_wins` (construct this directly with
  `Games.update_player!`, the same technique `resolve_win_test.exs` already
  uses for precise counts, rather than routing it back through a real kill —
  a decisive kill made through the domain would already have finished the
  game via rule 1, never reaching `end_night` in a `:night` state at all)
  finishes the game and leaves no day `Phase` row for that call, with the
  night phase closed as `AdvancePhase` already left it (rules 9, 10); a
  night whose counts decide `:continue` transitions to a fresh, open day
  phase exactly as before this bead, matching every pre-existing
  `end_night!` assertion unmodified (rule 11).
- End to end: one path through the domain code interface, extending the
  style of the existing `"end to end"` describe block
  (`test/werewolf_ash/games/action_test.exs:389-476`), spanning two full
  day/night cycles so the same seer can investigate twice (a seer may cast
  only one `:investigate` per phase — `one_per_actor_per_phase_per_type` —
  so a wolf and a non-wolf target cannot both be investigated in the same
  night): start a game, day one the bodyguard protects a target, `end_day`,
  night one a werewolf's kill lands on a different (non-decisive) target
  while the seer investigates the werewolf — assert `result: %{"is_werewolf"
  => true}` (rule 8) — then `end_night` — assert the game is now in a fresh
  `:day` phase (rule 11: dawn's check here decides `:continue` and changes
  nothing further), the killed player is still dead, and nothing about the
  investigation or the protection changed (rules 1, 4, 6, 8, 11 together),
  day two nothing happens, `end_day`, night two the seer investigates a
  non-wolf player this time — assert `result: %{"is_werewolf" => false}`.
  Together these two investigations are the bead's `Done:` line's own "seer
  result correct for wolf and non-wolf," which a single-target investigation
  cannot pin on its own.

### Existing tests this will break

Grep for every call site this bead's rules could touch:

```
grep -rn "create_kill_action\|end_night\|ApplyKill\|ResolveWin\|CheckWin" lib/ test/ --include="*.ex" --include="*.exs"
```

Hits, by file (re-run against the current tree — `werewolf_ash-qss.18` has
already merged since this bead was first drafted and shifted several line
numbers in `action.ex`/`action_test.exs`; the numbers below are current, not
the ones an earlier revision of this spec cited):

- `lib/werewolf_ash/games.ex:25,47` — the code interface definitions
  (`end_night`, `create_kill_action`).
- `lib/werewolf_ash/games/action.ex:18,105` — `ApplyKill`'s alias and its
  `change` in the `:kill` action (the `:kill` action block itself is now
  lines 88-106, after qss.18's own validations were added ahead of it).
- `lib/werewolf_ash/games/game.ex:11,44,103` — the moduledoc mention and the
  `end_night` transition/action.
- `lib/werewolf_ash/games/reactors/resolve_win.ex` and `check_win.ex` — the
  modules themselves (qss.8, unchanged by this bead).
- `lib/werewolf_ash/games/action/changes/apply_kill.ex:1` — the module
  itself.
- `test/werewolf_ash/games_test.exs:223,253,336,345` — `end_night!`/
  `end_night` calls in the "phase transitions" describe block.
- `test/werewolf_ash/games/reactors/check_win_test.exs` and
  `resolve_win_test.exs` — qss.8's own tests, calling the reactors directly,
  never through `create_kill_action` or `end_night`.
- `test/werewolf_ash/games/action_test.exs:160,247,261,271,284,287,292,304,
  314,328,331,341,343,354,358,361,375,397,407,428,437,440,457` — every
  `end_night!`/`create_kill_action` call in that file (261 is the
  `describe "create_kill_action/3,4" do` line itself, matched on the
  substring), across all three describe blocks (`"create_action/4,5"`,
  `"create_kill_action/3,4"` at line 261, `"end to end"` at line 389 —
  qss.18 added new tests to all three, including two that call `end_night!`
  where none did before: "rejects consecutive-day protection..." at line 154
  and the "bodyguard path" end-to-end test at line 390).
- `test/werewolf_ash/games/action/changes/apply_kill_test.exs:1,10,21` —
  the module alias and the direct `ApplyKill.change/3` invocation.

**No currently-passing assertion's expected value changes under rules 1-11
as specified**, including the tests qss.18 added since this spec was first
drafted.

- Every `create_kill_action`/`create_kill_action!` call in `action_test.exs`
  is made against `started_game/0`'s fixture (`action_test.exs:18-31`): 5
  players dealt 1 werewolf, 1 seer, 1 bodyguard, 1 hunter, 1 villager (qss.3's
  `max(1, div(5,4)) = 1` werewolf formula). Every kill test there kills at
  most one target, and the one test that attempts a kill twice
  (`"a dead-target kill is refused without spending the phase's one kill"`,
  `action_test.exs:336-347`) has its first attempt rejected by qss.18's
  `TargetAlive` validation before `ApplyKill`/rule 1 ever runs — only the
  second, successful attempt lands, taking non-wolves from 4 to 3.
  `1 >= 3` is false, so rule 1's win check decides `:continue` in every kill
  test in this file: `state` stays `:night` (the state these tests already
  run in), which is what they already assume implicitly (none of them assert
  on `.state`, confirmed by `grep -n "\.state ==" test/werewolf_ash/games/action_test.exs
  test/werewolf_ash/games/action/changes/apply_kill_test.exs`, which returns
  no hits).
- Every `end_night!` call in `action_test.exs` and `games_test.exs`,
  including the two qss.18 added (`action_test.exs:160,397,407`), runs on a
  night containing no `:kill` action at all — none of these tests create one
  in the same phase they call `end_night!` from. Living counts at every one
  of those calls are 1 werewolf against 4 non-wolves (nobody has died):
  `CheckWin.decide(%{wolves: 1, non_wolves: 4})` is `:continue`
  (`check_win.ex:83`), so rule 9's new dawn check changes nothing about any
  of them, and rule 6 (no kill re-resolution) was already true before this
  bead touched anything about a kill in the same phase — none of them assert
  about `Action` rows either.
- `Games.end_day`/`Games.end_night` at `games_test.exs:336,345` are made on
  games whose `state` does not match either transition's `from:` (`:lobby`,
  then `:day`) and are asserted to return `NoMatchingTransition`. Rule 9's
  new change is a *second* `change` on `:end_night`; when `AshStateMachine`'s
  own transition validation invalidates the changeset (the state mismatch),
  no `change`'s `after_action` hook ever runs for either change, so rule 9's
  logic is never reached and the existing `NoMatchingTransition`/"a rejected
  transition writes nothing" assertions are unaffected.

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

- `lib/werewolf_ash/games/action.ex` — the `:kill` action block (now lines
  88-106, after qss.18's own validations), to add the new `change` after
  `ApplyKill`.
- A new module under `lib/werewolf_ash/games/action/changes/`, or wherever
  the coder judges the win-check composition belongs, implementing rules 1-5.
- `lib/werewolf_ash/games/game.ex` — the second `change` appended to
  `:end_night` (rules 9-11).
- A new module under `lib/werewolf_ash/games/game/changes/` for
  `end_night`'s new dawn-check change (rules 9-11).
- `lib/werewolf_ash/games.ex` — add `define :destroy_phase, action:
  :destroy` to the `Phase` resource block (`Phase` already has a primary
  `:destroy` action via its own `defaults [:read, :destroy]`,
  `lib/werewolf_ash/games/phase.ex:22`; it is simply not yet exposed through
  the domain, and rule 10 is the first caller that needs it).
  `docs/specs/werewolf_ash-qss.5.md`'s own Touches independently adds this
  same `define :destroy_phase, action: :destroy` line for its own
  (dusk-side) equivalent of rule 10 — the two beads were written in parallel
  and neither depends on the other. Whichever of
  `werewolf_ash-qss.5`/`werewolf_ash-qss.6` merges second should find the
  line already present in `games.ex` and reuse it rather than adding a
  second, duplicate `define` for the same action.
- `lib/werewolf_ash/games/reactors/resolve_win.ex` — read-only; its own
  moduledoc already warns that a stale `game` struct passed in would carry
  stale state into the `finish` transition (`resolve_win.ex:13-15`), which is
  why the composed `game` must be loaded fresh in each case: rule 1's caller
  via the kill's `phase_id` → `Phase.game_id` → `Games.get_game!/1,2`, and
  rule 9's caller via the record `AdvancePhase`'s own hook already produced
  — never a struct fetched earlier or reused from anywhere else in either
  request.
- `async?: false` is a hard requirement, not advisory, for both compositions
  — see rules 1 and 9. It also matches the only two existing call sites of
  these reactors, `check_win_test.exs:10` and `resolve_win_test.exs:9`.
- `test/werewolf_ash/games/action_test.exs` — new cases in the
  `"create_kill_action/3,4"` and `"end to end"` describe blocks.
- A new test file alongside `apply_kill_test.exs` for the win-check
  composition module's own direct unit tests.
- A new test file under `test/werewolf_ash/games/game/changes/` for
  `end_night`'s new dawn-check change's own direct unit tests.
- `test/werewolf_ash/games_test.exs` — new cases in "phase transitions" for
  rules 9-11, though `action_test.exs` may be the more natural home since it
  already has kill fixtures.
- The precedent for chaining two independently-hooked `Ash.Resource.Change`
  modules inside one action already exists in this codebase: `Game`'s
  `:start` action runs `change DealRoles` then
  `change {AdvancePhase, to: :by_clock}` (`lib/werewolf_ash/games/game.ex:86-87`),
  each registering its own `after_action` hook
  (`deal_roles.ex:21`, `advance_phase.ex:43-45`). Both the `:kill` action's
  new second change and `:end_night`'s new second change can follow the same
  shape.
