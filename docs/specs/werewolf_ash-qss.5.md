# werewolf_ash-qss.5: EndDay Reactor: lynch resolution

Depends on: none

## For the owner

**What changes.** When the village's daytime vote period ends, the game now
actually counts it: whoever got the most votes is lynched and dies
immediately, a tie means nobody dies, and if nobody voted, nobody dies
either. Right after that, the game checks whether either side has already
won — if so, the game ends there and there is no night. For now, if the
hunter is the one lynched, they just die with no last shot; the "shoot
back" window arrives in a later change.

**Decisions for you.**
1. Should a vote still count if the voter died (some other way) before the
   day ended? — Options: count it (a cast vote is final) or discard it.
   **Recommended:** count it — matches the existing "a vote is final once
   cast" rule.
2. Should a vote still count if its named target died before the day
   ended? — Options: count it (a lynch on an already-dead target just does
   nothing extra) or discard it. **Recommended:** count it, since it
   changes nothing either way.
3. If the vote ends the game right at dusk, should the game skip opening
   night at all, or is a brief, harmless zero-length night record in the
   game's history acceptable? — Options: skip opening night (touches the
   already-built day/night handoff code) or leave the zero-length night.
   **Recommended:** leave it — it is invisible to players and avoids
   touching working code.

**Rule changes.** Extends "a villager's vote is final once cast": a vote
already cast still counts in the tally even if the voter or the named
target dies before that day's vote is resolved.

## Goal

Today, `end_day` (`lib/werewolf_ash/games/game.ex:90-101`) only moves the
clock: it transitions the game to `:night` and opens the next phase, and
every `:vote` action cast during the day is inert — nothing ever reads it.
After this bead, calling `end_day` also resolves the day itself: it counts
the votes cast in that day phase, lynches whoever holds a strict plurality
(a tie lynches no one, matching the epic's settled rule), and checks whether
the village or the wolves have just won. If they have, the game ends there
instead of moving on to night. If not, the night begins exactly as it does
today. A lynched hunter simply dies here — the 1-hour shooting window is
qss.7's addition, built on top of this bead.

## Assumptions

The bead's description and `Done:` line are silent on two edge cases that a
real game can hit once players start dying outside the tidy path the tests
exercise today. Both are resolved here rather than left for the coder to
guess, and both are easy to reverse if the owner disagrees.

- **A1 — a voter who died before the day ended.** No mechanism in the
  currently-merged code can kill a player mid-day (the only kill path is the
  night-only `:kill` action), so this is unreachable today, but qss.7's
  hunter hand-off will make it reachable (a lynched hunter's shot happens
  inside the same day). Assumption: the vote still counts. The epic's own
  settled rule is that every action, including a vote, "is used once per
  phase" and is final the instant it is cast (`CLAUDE.md`, and
  `WerewolfAsh.Games.Action`'s moduledoc, `lib/werewolf_ash/games/action.ex:6-10`);
  nothing revokes a cast vote retroactively, and re-checking every voter's
  live status at resolution time would be a second liveness rule invented
  here rather than asked for. See rule 8.
- **A2 — a vote whose target died before resolution.** Also unreachable
  today (nothing currently lets a target die between being voted for and
  `end_day` running) and also not addressed by any rule. Assumption: the
  vote still counts toward that target's tally, and if that target turns out
  to hold the plurality, applying the lynch to them is a harmless no-op —
  their `alive` was already `false`, and setting it to `false` again changes
  nothing. This avoids inventing a second, different liveness check at
  resolution time, and keeps the resolver a pure function of "who voted for
  whom" rather than needing to reload every target's current status before
  it can decide. See rule 9. (qss.18 will later stop a vote from ever naming
  a dead target at cast time; once that lands this case becomes structurally
  unreachable rather than merely assumed away.)


**Flagged for the owner: a win at dusk leaves a zero-length night phase.**
The lynch and win check run after `AdvancePhase` has already opened the night,
so when the lynch ends the game, the finished game keeps a night `Phase` row
whose `started_at` equals its `ended_at`. The bead's original order was win
check first, then night. This spec keeps the current order to avoid changing
the merged `AdvancePhase`; the owner may prefer the win check to run before the
night opens. qss.19's dusk notice must not announce night for a finished game
either way; that is recorded on its bead.
## Rules

1. `WerewolfAsh.Games.Reactors.ResolveLynch.tally/1` takes the list of
   `:vote` `WerewolfAsh.Games.Action` structs recorded in a day phase and
   returns a map from target player id to the list of actor (voter) player
   ids who voted for that target. A target nobody voted for is absent from
   the map. An empty input list returns an empty map. Any action in the input
   whose `type` is not `:vote` is ignored.
2. `WerewolfAsh.Games.Reactors.ResolveLynch.decide/1` takes a tally (the
   shape `tally/1` returns) and returns `{:lynch, target_id}` when exactly
   one target holds the strict maximum vote count.
3. `decide/1` returns `:no_lynch` when two or more targets are tied for the
   maximum vote count.
4. `decide/1` returns `:no_lynch` for an empty tally (nobody voted that
   day).
5. The votes tallied are exactly the `:vote` actions belonging to one
   specific day phase, and that phase is given to
   `WerewolfAsh.Games.Reactors.ResolveLynch` directly as an input
   (`phase_id`, alongside `game_id` for the win check) — the reactor never
   (re)derives "the current day phase" from the game's own state or from
   which phases are open or closed. For `end_day` specifically, that input
   is the phase that was open on the game at the moment `end_day` was
   called, captured before `end_day`'s own transition runs (see "Touches"
   for why capturing it early, rather than looking it up after the
   transition, is required and not just tidier). This is also what lets
   qss.15 invoke the same reactor at its own vote deadline, while the day
   phase is still open, without the reactor changing at all — it needs only
   the id of the phase whose votes to count, whatever state the game is in
   when it's called.
6. When resolution decides `{:lynch, target_id}`, that player's `alive`
   becomes `false`.
7. When resolution decides `:no_lynch`, no player's `alive` changes as a
   result of the vote.
8. A vote cast by a player who was alive at the moment they voted counts in
   the tally even if that player is no longer alive by the time `end_day`
   resolves (Assumption A1).
9. A vote naming a target who is no longer alive by the time `end_day`
   resolves still counts toward that target's tally; if that target is the
   plurality choice, applying the lynch to them changes nothing (Assumption
   A2).
10. The lynch resolution applies no bodyguard-protection check of its own: a
    `:protect` action never prevents a lynch. Protection
    (`WerewolfAsh.Games.Action.Changes.ApplyKill`,
    `lib/werewolf_ash/games/action/changes/apply_kill.ex`) only ever shields
    its target from that same night's werewolf kill; do not port or
    reference that check here.
11. A lynched hunter dies exactly like any other lynched player in this
    bead: no `hunter_pending` entry, no shooting window, no other
    hunter-specific branching. (qss.7 adds that later, the same seam qss.6
    leaves for it on the night side.)
12. After the lynch is applied (or not), `end_day` checks the win condition,
    whether or not a lynch occurred, by composing
    `WerewolfAsh.Games.Reactors.ResolveWin`
    (`lib/werewolf_ash/games/reactors/resolve_win.ex`), which in turn
    composes `WerewolfAsh.Games.Reactors.CheckWin`. This bead does not
    reimplement or fork that decision.
13. If the win check finds a winner, `end_day` finishes the game
    (`state: :finished`, `winner` set to `CheckWin.winner/1`'s result)
    instead of transitioning to night.
14. When rule 13 applies, no phase is left open afterward: no `Phase` row
    for that game has `ended_at: nil` once `end_day` returns.
15. If the win check finds no winner, `end_day` transitions the game to
    `:night` exactly as it does today — `phase_ends_at` computed from the
    game's clock/timezone windows, the day phase closed, a new night phase
    opened — and every existing test of that path
    (`test/werewolf_ash/games/game/changes/advance_phase_test.exs`,
    `test/werewolf_ash/games_test.exs`'s "phase transitions" describe block)
    keeps passing unmodified. See "Touches" for how to add rules 1-14
    without touching `AdvancePhase` or its tests at all.
16. The `Reactor.run/4` call that runs `WerewolfAsh.Games.Reactors.ResolveLynch`
    from inside `end_day`'s hook must pass `async?: false` as part of its
    `options` (the 4th positional argument —
    `Reactor.run(reactor, inputs \\ %{}, context \\ %{}, options \\ [])`,
    `deps/reactor/lib/reactor.ex:212`, validated against `@run_schema`,
    `deps/reactor/lib/reactor.ex:152`, whose `async?` entry defaults to
    `true`, `deps/reactor/lib/reactor.ex:170-174`). Passing it once, at this
    single outer call, is sufficient: `ResolveLynch`'s own `compose
    :resolution, ResolveWin` step (and `ResolveWin`'s own composition of
    `CheckWin`) each compute their child's `async?` from the *parent's*
    context rather than from a separately-specified option
    (`child_async? = parent_async? and allow_async?`,
    `deps/reactor/lib/reactor/step/compose.ex:69-70`), so `async?: false` on
    the outermost run cascades through both composed layers. Left at the
    default, every read/update step (including the ones composed in from
    `ResolveWin`/`CheckWin`) runs inside a task started by
    `Task.Supervisor.async_nolink/4`
    (`deps/reactor/lib/reactor/executor/async.ex:73`) — a different process,
    and in production a different pool connection, from the one running
    `end_day`'s own hook. `end_day`'s `Player`/`Game`/`Phase` writes run
    inside the update action's own transaction
    (`deps/ash/lib/ash/actions/update/update.ex:681` wraps the changeset's
    changes in `transaction?: Keyword.get(opts, :transaction?, true) &&
    changeset.action.transaction?`, true by default here), so a task on
    another connection cannot see this transaction's uncommitted writes: a
    lynch that should reach wolf parity would be read back as not having
    happened, and the win check would wrongly decide `:continue`. **No test
    in this bead's suite can catch a missing `async?: false`**:
    `DBConnection`'s ownership pool resolves a checkout through the calling
    process's `$callers` list, "set by default for tasks from Elixir v1.8"
    (`deps/db_connection/lib/db_connection/ownership.ex:55-64`), so under
    `mix test`'s shared Ecto sandbox (`test/support/data_case.ex:33`) a
    spawned task still finds the test's checked-out connection and the async
    and synchronous paths behave identically; they diverge only in
    production. Per the project's own convention for this
    (`CLAUDE.md:106`), the code-reviewer must verify this rule by reading
    the call site, not by running the suite.

    Running synchronously also prevents a deadlock, not just a stale read: `end_day`
    holds an uncommitted update on the game's row, and an async `ResolveWin` would try
    to `finish` that same row from a second connection and wait on the lock forever. On
    the caller's connection, `finish` runs inside the transaction that already holds it.
## Out of scope

- **Hunter hand-off** (qss.7): entering `hunter_pending`, the 1h window,
  `shoot`, the random fallback. Rule 11 only pins that a dead hunter is a
  plain death *for now* — do not add a role check anywhere in this bead's
  code, not even as a no-op branch.
- **Moving resolution to a vote deadline before dusk** (qss.15): this bead's
  reactor takes `phase_id`/`game_id`, not a `now`, does its own work with no
  clock dependency, and is never told "the current phase" implicitly (rule
  5) — specifically so qss.15 can later invoke the same reactor at its own
  vote deadline, while the day phase is still open, with no change to the
  reactor at all. Do not wire any second trigger, deadline attribute, or
  scheduler hook here — that is qss.15's and qss.9's job.
- **Recording what happened on `Phase.summary`**: the `Phase` resource has a
  `summary :map` field and one existing generic test exercises it with an
  example key `"lynched"` (`test/werewolf_ash/games_test.exs`'s "phases"
  describe block, "can be closed with a summary"), but no rule anywhere asks
  this bead to populate it, and how a day's outcome is surfaced to players is
  qss.19's open design question ("how an announcement is stored and
  delivered"). Do not write to `summary` here — leave that decision to
  qss.19.
- **Vote visibility** (qss.16): who may see the running tally, and when.
  qss.16 depends on this bead specifically to reuse `tally/1` rather than
  compute its own; do not add any authorization or filtering to `tally/1`,
  and do not expose the tally through any interface here.
- **Target/actor validity** (qss.18): no check that a vote's target is
  alive at cast time, no cross-game actor/target/phase check, no
  consecutive-protect rule. This bead's rules 8-9 exist precisely because
  qss.18 has not landed yet; once it has, those cases become structurally
  rarer but this bead's behaviour under them does not need to change.
- **Configurable setup** (qss.14): role distribution, werewolf count,
  optional specials, min/max players are untouched. Tests here may use
  whatever fixed player counts are convenient, including bypassing the full
  lobby/start flow the way `apply_kill_test.exs` and `resolve_win_test.exs`
  already do, when a test needs precise living counts.
- **Modifying `WerewolfAsh.Games.Game.Changes.AdvancePhase`**
  (`lib/werewolf_ash/games/game/changes/advance_phase.ex`): its `change/3`,
  its clock computation, and its phase-opening logic are unchanged. This
  bead's new logic is a separate `change` appended after it in `end_day`'s
  list — see "Touches" for the existing precedent for chaining two
  independently-hooked changes on one action.
- **Announcing the lynch result** (qss.19): no chat message, no feed event.
  This bead only changes `Game`, `Phase` and `Player` rows.
- **Full role reveal at game over** (qss.17): `finish` already sets
  `winner`; this bead adds nothing to what becomes visible when a game ends.
- **GraphQL/API exposure and authorization** (the `27w` epic, including
  27w.2's policies): `end_day` keeps its current code-interface signature
  and actor handling; nothing here is exposed to or gated for a caller.
- **Any database migration**: this bead adds no resource attribute, so
  `mix ash.codegen` has nothing new to generate.

## Acceptance

- `WerewolfAsh.Games.Reactors.ResolveLynch.tally/1` — direct unit tests:
  groups votes by target into voter-id lists (rule 1); a target with no
  votes is absent, not a zero (rule 1); an empty list returns an empty map
  (rule 1, feeds rule 4). Include a non-vote action, such as a stray `:protect`, in the input and
  assert it is not counted (rule 1).
- `WerewolfAsh.Games.Reactors.ResolveLynch.decide/1` — direct unit tests: a
  single plurality winner (rule 2); a two-way tie at the top (rule 3); an
  empty tally (rule 4). Also a 2-1-1 case: a tie among the lower vote counts must still lynch the
  single leader, which catches a decide that checks for a tie anywhere
  rather than at the top.
- `WerewolfAsh.Games.Reactors.ResolveLynch` (the reactor, run the way
  `check_win_test.exs:10` and `resolve_win_test.exs:9` already run
  `CheckWin`/`ResolveWin` — `Reactor.run(ResolveLynch, %{phase_id: phase.id,
  game_id: game.id}, %{}, async?: false)`, rule 16) — direct tests composing
  the whole thing: a plurality lynch kills the target and leaves the game
  running when the win check decides `:continue` (rules 6, 12, 15); a
  plurality lynch that removes the last living wolf finishes the game as
  `:village` (rules 6, 12, 13, 14); a tied vote kills nobody and still runs
  the win check (rules 3, 7, 12); a vote from a since-dead voter still
  counts (rule 8, A1); a vote for a since-dead target still counts and the
  harmless-no-op re-kill does not error (rule 9, A2); an existing `:protect`
  action for the lynched player does not save them (rule 10); votes cast in
  an earlier phase of the same game are not counted when a different
  phase's id is given (rule 5). Rule 16's `async?: false` itself has no
  passing/failing test that distinguishes it (that rule explains why) — the
  code-reviewer checks it by reading the call site.
- The new `Ash.Resource.Change` wired into `Game`'s `:end_day` action (name
  advisory) — direct unit test(s) on its own contract, staged the way
  `apply_kill_test.exs:12-25`'s `stage/3` helper stages `ApplyKill` (build a
  bare changeset, call the module's `change/3`, pull the lone hook off the
  changeset, invoke it by hand) rather than only exercising it indirectly
  through `end_day!`.
- End to end, through the code interface: cast votes with
  `Games.create_action!/4`, then `Games.end_day!/1,2` —
  - a plurality lynch that does not end the game: the target's `alive` is
    `false` afterward and the game is in `:night` (rules 6, 15);
  - a plurality lynch that removes the last living wolf: `Games.end_day!`
    returns a game with `state: :finished`, `winner: :village`, and no
    `Phase` row for that game has `ended_at: nil` (rules 6, 12, 13, 14).
- Rule 5: votes cast in a different day phase of the same game are not
  counted. Resolve one day phase while another day phase holds votes for a
  different target, and assert only the resolved phase's votes decide.
- Rule 11: a lynched hunter is a plain death. `alive` is `false`, the game
  moves on to night (or finishes, per the win check), and nothing enters
  `hunter_pending`.
- Regression (no new test needed, just confirm unmodified):
  `test/werewolf_ash/games/game/changes/advance_phase_test.exs`'s two
  `:end_day` changeset-construction tests (lines 34-48 and 72-83) keep
  passing without edits (rule 15).
- Fix required (see "Existing tests this will break"): two tests in
  `test/werewolf_ash/games/action_test.exs` each cast a single day vote
  naming the game's sole werewolf and then rely on the werewolf still being
  alive afterward — `182-195` ("a different type in the same phase...") and
  `293-323` ("day/night path..."). Both need a second, opposing vote added
  so the day ties and nobody is lynched.

## Touches

Advisory only.

- `lib/werewolf_ash/games/reactors/resolve_lynch.ex` (new) — the reactor,
  mirroring `lib/werewolf_ash/games/reactors/check_win.ex` and
  `resolve_win.ex`'s style: pure helpers (`tally/1`, `decide/1`) plus
  `read`/`update`/`compose` steps, taking `phase_id` and `game_id` as inputs
  (rule 5) and reloading whatever it needs fresh from those ids rather than
  accepting structs from the caller — matching `CheckWin`'s own `game_id`
  (not `game`) input style, and avoiding any question of whether a passed-in
  struct is stale.
- `lib/werewolf_ash/games/game.ex:90-101` — the `:end_day` action gains a
  second `change`, appended after the existing `{AdvancePhase, to: :night}`.
  The precedent for chaining two independently-hooked `Ash.Resource.Change`
  modules on one action already exists on `:start`: `change DealRoles` then
  `change {AdvancePhase, to: :by_clock}` (`game.ex:86-87`), each registering
  its own `after_action` hook (`deal_roles.ex:21`, `advance_phase.ex:43-45`).
- A new module, likely under `lib/werewolf_ash/games/game/changes/`,
  implementing rules 1-16.
- **The new change's `change/3` must capture the day phase's id
  synchronously, before registering any hook — not look it up from inside
  the hook.** `changeset.data` is the game record as it was before this
  `end_day` call touched anything, so `Ash.load!(changeset.data,
  :current_phase, Context.to_opts(context))` (or an equivalent query by
  `game_id` + `is_nil(ended_at)`) run directly in `change/3`'s own body,
  synchronously, is guaranteed to find the day phase that is still open at
  that exact point — before `AdvancePhase`'s own change runs at all, let
  alone its hook. Close over that phase's id (and `changeset.data.id` as
  `game_id`) when building the deferred hook that calls `Reactor.run`. Do
  *not* try to find "the day phase" from inside a hook that runs after
  `AdvancePhase`'s: by then `AdvancePhase` has closed it (set `ended_at`,
  `advance_phase.ex:70-74`) and opened a new phase in its place, so any
  lookup keyed on "the currently open phase" would find the *new night*
  phase instead, and a lookup keyed on "the day phase" would have no
  `is_nil(ended_at)` match at all — this is exactly the trap rule 5 is
  written to avoid, and it is also why the reactor takes an explicit
  `phase_id` rather than deriving one itself.
  - This synchronous capture is safe against
    `advance_phase_test.exs`'s two changeset-only tests (`lines 34-48`,
    `72-83`): both build their changeset from a bare, unpersisted `%Game{}`
    struct (`id: nil`, `advance_phase_test.exs:11-16`), so
    `Ash.load!(changeset.data, :current_phase, ...)` resolves to `nil`
    (`game_id == nil` matches no `Phase` row) rather than raising. The new
    change must not turn that `nil` into a changeset error — it should just
    close over `phase_id: nil` and let the (never-invoked, on these two
    tests) hook be the only place that would ever act on it. This is what
    keeps rule 15's regression true.
  - Still register the hook itself (the one that runs the reactor, kills
    the target, and finishes the game if there's a winner) as an
    `after_action` hook placed after `AdvancePhase`'s, for the same reasons
    as before: `Ash.Changeset` runs `before_action`/`after_action` hooks in
    the order they were registered — both default to appending
    (`deps/ash/lib/ash/changeset/changeset.ex:7139-7147` for
    `before_action`, `:7284-7303` for `after_action`), walked in that list
    order (`:4985-5002`) — so registering after `AdvancePhase`'s own
    `change/3` call means this hook runs once the game row already shows
    `:night` and the new night `Phase` is already open.
    - `Game.finish`'s transition already allows `from: [:day, :night,
      :hunter_pending]` (`game.ex:45`), so finishing from `:night` here is a
      normal, valid transition, not a workaround.
    - The reactor reloads the game fresh from `game_id` before composing
      `ResolveWin` (see the reactor bullet above) rather than being handed
      a struct from earlier in the request — `ResolveWin`'s own moduledoc
      warns a stale struct would carry stale state into `finish`
      (`resolve_win.ex:13-15`), and qss.6's spec requires the same
      reload discipline for its own, independent composition of
      `ResolveWin`.
    - If there is a winner, rule 14 requires closing the night phase
      `AdvancePhase` just opened (otherwise it is the one `Phase` row left
      with `ended_at: nil`) as part of the same hook, rather than leaving it
      dangling.
  - This is exactly why rule 15's regression holds: `AdvancePhase`'s own
    behaviour, and `advance_phase_test.exs`'s coverage of it (built via
    `Changeset.for_update` without ever calling `Ash.update!`, so no hook —
    from either change — ever runs), are untouched.
- `test/werewolf_ash/games/reactors/resolve_lynch_test.exs` (new).
- A new test file alongside `advance_phase_test.exs`/`apply_kill_test.exs`
  for the new change's own direct unit tests.
- `test/werewolf_ash/games_test.exs` — new end-to-end cases in "phase
  transitions" or a new describe block.
- `test/werewolf_ash/games/action_test.exs:185` and `:298` — fixes required,
  not just a risk (see below).

### Existing tests this will break

Grep for every call site this bead's rules touch:

```
grep -rn "end_day\b" lib/ test/ --include="*.ex" --include="*.exs"
```

Hits:

- `lib/werewolf_ash/games.ex:24` — the code interface definition.
- `lib/werewolf_ash/games/game.ex:11,43,90` — moduledoc mention, the
  `end_day` transition, and the `end_day` action itself.
- `lib/werewolf_ash/games/game/changes/advance_phase.ex:9` — moduledoc
  mention only.
- `test/werewolf_ash/games/game/changes/advance_phase_test.exs:38,79` —
  changeset-construction tests, discussed above (rule 15, unaffected: they
  never call `Ash.update!`, so neither `AdvancePhase`'s nor the new change's
  hooks ever run for them).
- `test/werewolf_ash/games_test.exs:170,239,251,294` — the "phase
  transitions" describe block. Confirmed by
  `grep -n ":vote" test/werewolf_ash/games_test.exs`, whose only hits are in
  a separate "actions" describe block (lines 550-592) that creates its
  `Phase` directly via `Games.create_phase!` and never calls `end_day` at
  all — so none of these `end_day!`/`end_day` calls ever have a `:vote`
  action sitting in their day phase. Every game reaching `end_day!` here was
  built through `ready/1` (`games_test.exs:141-146`) and, where roles
  matter, `Games.start_game!` (qss.3's `RoleAssignment.composition/1`,
  `lib/werewolf_ash/games/game/role_assignment.ex:20-25`, deals 1 werewolf
  against 4 non-wolves for a 5-player game). With no votes cast, rules 1-4
  decide `:no_lynch` and rule 12's win check sees 1-vs-4 living, which
  `CheckWin.decide/1` (`check_win.ex:83-86`) never finishes — `:continue`.
  Rule 15 keeps every one of these assertions (`state`, `phase_ends_at`,
  the `phases/1` shape) exactly as they are today.
- `test/werewolf_ash/games/action_test.exs:63,94,115,129,143,190,209,300,
  333` — every `end_day!` call in this file. Confirmed by
  `grep -n ":vote" test/werewolf_ash/games/action_test.exs` (hits: lines 50,
  102, 114, 119, 172, 175, 185, 194, 201, 298, 304): of those, only 172, 185
  and 298 cast a vote that is still standing (no later action on the same
  target/phase clears it) at the time some `end_day!` call in the same test
  runs. **Two of those three are real breaks — line 185 was missed in an
  earlier revision of this spec and line 298's proposed fix in that revision
  was itself wrong; both are corrected below.** Line 172's vote
  (`p.villager.id -> p.werewolf.id`, inside "refuses a second action of the
  same type in the same phase (rule 9)", `action_test.exs:167-179`) is
  unaffected: that test never calls `end_day!` at all.

```
grep -n ":vote" test/werewolf_ash/games/action_test.exs
```

**Break 1: `test/werewolf_ash/games/action_test.exs:182-195`**, "a different
type in the same phase, or the same type in a later phase, still succeeds".
Line 185 casts `Games.create_action!(day.id, p.villager.id, p.werewolf.id,
:vote)` — a single vote naming the game's *only* werewolf (`started_game/0`,
`action_test.exs:17-29`, deals exactly 1 werewolf among 5 players). Line 190
calls `Games.end_day!(game, %{now: @dusk})`: under rules 1-2 that lone vote
is a plurality of one, so rule 6 lynches the werewolf, rule 12's win check
then sees 0 living wolves, and rule 13 finishes the game as `:village`
before night ever opens. Line 191, `Games.end_night!(game, %{now: @dawn})`,
then raises `NoMatchingTransition` — `end_night`'s `from: :night` (`game.ex:44`)
does not match a `:finished` game. **The test's expectation is stale**, not
the new rule: this test's own purpose (per its name) is that a different
action type, or the same type in a later phase, still succeeds — it needs
*some* vote to exist that day, not one that decides the game.

**Break 2: `test/werewolf_ash/games/action_test.exs:293-323`**, "day/night
path: bodyguard protects, a vote lands, a kill lands, the seer investigates".
Line 298 casts the same shape of vote (`p.villager.id -> p.werewolf.id`).
Line 300's `Games.end_day!` lynches the werewolf and finishes the game the
same way. `night = current_phase(game)` at line 301 then cannot return a
usable night phase (rule 14: no phase is left open), and even if it could,
line 307's `Games.create_kill_action!(night.id, p.werewolf.id, target.id)`
would raise — its actor is now dead, and `:kill`'s unconditional
`ActorAlive` validation (`action.ex:81`) rejects it. Stale for the same
reason as Break 1: the test's own purpose is to exercise the *night's* kill
and investigate flow, and it only needs *some* day-phase action to reach
night.

**The fix for both, and why simply retargeting the vote does not work:** an
earlier revision of this spec proposed retargeting line 298's vote to
`p.villager.id` instead of the werewolf. That is wrong: `p.villager` is the
*actor* of two later calls in the same test that each expect exactly one
error —
`assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
Games.create_action(night.id, p.villager.id, p.werewolf.id, :vote)`
(lines 303-304, rejected today only for being a `:vote` at night) and
`assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
Games.create_kill_action(night.id, p.villager.id, p.bodyguard.id)`
(lines 315-316, rejected today only for a non-werewolf actor). Ash
validations accumulate every failing check rather than stopping at the
first, so a dead `p.villager` attempting either would *also* fail
`ActorAlive` (unconditional for `:vote` and for `:kill`,
`action.ex:49,81`), adding an `:actor_id` error alongside the existing
`:type` one; the one-element pattern `errors: [%{field: :type}]}` does not
match a two-element list, so both assertions would fail. Retargeting to
`p.villager.id` therefore breaks two *more* lines than it fixes.

The correct fix for both tests is to make the day tie instead of adding a
target that turns out to matter later: add a second, opposing vote —
`Games.create_action!(day.id, p.werewolf.id, p.villager.id, :vote)` —
immediately after the existing one, in each test. That gives the werewolf
and the villager one vote each (a tie), so rules 3 and 7 apply: nobody is
lynched and every player's `alive` is unchanged. In Break 1, `end_night!`
(line 191) and `day2`'s own fresh vote (line 194) then run exactly as they
do today. In Break 2, `night`'s kill, the seer's investigation, and the
three rejected-action assertions (lines 303-304, 315-316, 318-319) then run
exactly as they do today, since every actor and target they reference is
still alive.

No other file references `end_day`, `:vote`, or these reactors outside
what's listed above — confirmed by the two greps run above plus
`grep -rn "ResolveWin\|CheckWin" lib/ test/ --include="*.ex" --include="*.exs"`,
whose only hits are `reactors/check_win.ex`, `reactors/resolve_win.ex`, and
their own two test files (`check_win_test.exs`, `resolve_win_test.exs`),
none of which call `end_day`.
