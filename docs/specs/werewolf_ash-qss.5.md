# werewolf_ash-qss.5: EndDay Reactor: lynch resolution

Depends on: none

## For the owner

**What changes.** When the village's daytime vote period ends, the game now
actually counts it: whoever got the most still-valid votes is lynched and
dies immediately, a tie means nobody dies, and if nobody voted, nobody dies
either. A vote cast by someone who has since died, or aimed at someone who
has since died, is dropped and doesn't count. Right after that, the game
checks whether either side has already won — if so, the game ends there and
there is no night. For now, if the hunter is the one lynched, they just die
with no last shot; the "shoot back" window arrives in a later change.

**Decisions.**
1. Should a vote still count if the voter died (some other way) before the
   day ended? — **Decided:** No. A vote cast by a player who is no longer
   alive by the time the vote resolves is dropped from the tally.
2. Should a vote still count if its named target died before the day
   ended? — **Decided:** No. A vote naming a target who is no longer alive
   by the time the vote resolves is dropped from the tally.
3. If the vote ends the game right at dusk, should the game skip opening
   night at all, or is a brief, harmless zero-length night record in the
   game's history acceptable? — **Decided:** skip opening night. When a
   lynch at dusk ends the game, no night `Phase` row exists for it
   afterward, not even one that was created and then closed.

**Rule changes.** Replaces the earlier extension to "a villager's vote is
final once cast" with the opposite: "When the vote resolves, only living
players' current votes for living targets count" (owner decision
2026-09-13, already recorded in `CLAUDE.md`'s "Actions are used once" rule).

## Goal

Today, `end_day` (`lib/werewolf_ash/games/game.ex:90-101`) only moves the
clock: it transitions the game to `:night` and opens the next phase, and
every `:vote` action cast during the day is inert — nothing ever reads it.
After this bead, calling `end_day` also resolves the day itself: it counts
the still-valid votes cast in that day phase — a vote from a player who is
no longer alive, or naming a target who is no longer alive, is dropped
before anything is tallied — lynches whoever holds a strict plurality of
what's left (a tie lynches no one, matching the epic's settled rule), and
checks whether the village or the wolves have just won. If they have, the game ends there
instead of moving on to night. If not, the night begins exactly as it does
today. A lynched hunter simply dies here — the 1-hour shooting window is
qss.7's addition, built on top of this bead.

## Assumptions

The bead's description and `Done:` line were originally silent on two edge
cases that a real game can hit once players start dying outside the tidy
path the tests exercise today. This revision replaces the assumptions that
once filled that gap with an explicit owner decision — kept below only as
the record of what was assumed and why it changed. Neither A1 nor A2 is
itself a source of any rule any more; rules 8 and 9 are.

- **A1 — a voter who died before the day ended (superseded 2026-09-13).**
  No mechanism in the currently-merged code can kill a player mid-day (the
  only kill path is the night-only `:kill` action), so this is unreachable
  today, but qss.7's hunter hand-off will make it reachable (a lynched
  hunter's shot happens inside the same day). This spec originally assumed
  the vote still counts, reasoning from "a vote is final once cast"
  (`CLAUDE.md`). The owner decided the opposite, in chat on 2026-09-13: at
  resolution, only a currently-living voter's vote counts. See rule 8.
- **A2 — a vote whose target died before resolution (superseded
  2026-09-13).** Also unreachable today (nothing currently lets a target die
  between being voted for and `end_day` running) and also not previously
  addressed by any settled rule. This spec originally assumed the vote still
  counts toward that target's tally, and that applying a lynch to an
  already-dead plurality target is a harmless no-op. The owner decided the
  opposite, in chat on 2026-09-13: at resolution, a vote naming a
  currently-dead target is dropped and never reaches any target's tally —
  the "harmless no-op" reasoning no longer applies, because such a vote is
  now excluded before any lynch is decided, not applied to a dead player.
  See rule 9. (qss.18 will separately stop a vote from ever naming a dead
  target at cast time; once that lands, rule 9 still governs a target who
  dies *after* being voted for but before resolution.)


**Resolved 2026-09-13: a win at dusk leaves no night phase at all.** The
lynch and win check still run after `AdvancePhase`'s hook has already opened
the night (rule 5's discipline of capturing the day phase's id before any
transition runs is unaffected by this), so by the time a winner is found,
`AdvancePhase` has already created a night `Phase` row. The owner decided
the game's history must show no night phase at all when it ends at dusk
(card decision 3), not a zero-length one that was opened and then closed.
Rather than reordering the win check ahead of `AdvancePhase`, or touching
`AdvancePhase` itself, `end_day`'s own new change undoes what `AdvancePhase`
just did, in the same transaction, when there turns out to be a winner: it
destroys that night `Phase` row instead of merely closing it (rule 14).
`AdvancePhase` (`lib/werewolf_ash/games/game/changes/advance_phase.ex`)
itself is unmodified and behaves exactly as it does today, including for
this same call — it always opens night; this bead's own change is what
removes it again, and only when rule 13 applies. qss.19's dusk notice must
not announce night for a finished game either way; that is recorded on its
bead.
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
8. A vote cast by a player who was alive at the moment they voted is dropped
   before tallying if that player is no longer alive by the time `end_day`
   resolves: it never reaches `tally/1`'s input and does not count toward
   any target (owner decision 2026-09-13, `CLAUDE.md`'s "Actions are used
   once" rule; supersedes this spec's original Assumption A1, which had it
   counting).
9. A vote naming a target who is no longer alive by the time `end_day`
   resolves is dropped before tallying: it never reaches `tally/1`'s input
   and does not count toward that target's total, or toward anyone else's
   (owner decision 2026-09-13, `CLAUDE.md`'s "Actions are used once" rule;
   supersedes this spec's original Assumption A2, which had it counting as a
   harmless no-op). `tally/1` itself is unchanged (rule 1) — the votes it is
   handed for a phase are filtered to a living actor and a living target
   before it ever runs.
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
    instead of transitioning to night. The game's `state` never observably
    settles on anything but `:finished` as a result of this call — any
    transient value a state-machine transition passes through on the way
    there, invisible outside the transaction, is not what this rule
    constrains. `finish` (`game.ex:116-121`) only sets `winner` and
    transitions `state`; it does not clear `phase_ends_at`, so a game
    finished by this rule keeps whatever value `AdvancePhase` already
    computed for the night that never opens (the next dawn's instant) —
    this rule does not require, and no test should assert, that
    `phase_ends_at` is cleared or changed by finishing. The same is true of
    qss.6's own mid-night finish, which reaches `finish` the same way.
14. When rule 13 applies, `end_day` leaves no night `Phase` row for that
    game (owner decision 2026-09-13, card decision 3; supersedes this
    spec's original rule 14, which only required a night phase — always
    created — to be closed rather than left open): the night `Phase` row
    that `AdvancePhase`'s own hook already created for this call no longer
    exists once `end_day` returns, and the day phase that was open when
    `end_day` was called remains closed (`ended_at` set, as `AdvancePhase`
    already left it). This rule is scoped to `Phase` rows only — it says
    nothing about, and does not require changing, any other attribute
    `AdvancePhase` already set on the `Game` row itself (see rule 13 on
    `phase_ends_at`). Both of the following are true of the game's `phases`
    once `end_day` returns: no `Phase` row for that game has `ended_at:
    nil`, and no `Phase` row for that game has `kind: :night` with a
    `number` matching the one `AdvancePhase` assigned for this call.
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
17. The step that loads a phase's `:vote` `Action` rows (rules 1, 8, 9) must
    reuse `Action`'s existing `:read` action, filtered to that phase and to
    `:vote`, and must pass `authorize?: false` on that read. It must not
    introduce a second, differently-named read action on `Action` for this
    purpose. Both halves of this rule exist for the same reason, and matter
    regardless of the order qss.5 and the unmerged, independent
    `werewolf_ash-27w.2` (Policies on Games resources — neither bead depends
    on the other) happen to land in: 27w.2's own spec restricts `Action`'s
    `:read` action by name to an actor holding a seat in that row's game
    (`docs/specs/werewolf_ash-27w.2.md`, rule 8: "an actor may read an
    `Action` row only while they hold a seat ... in that row's phase's
    game"), while leaving every `Action` action *not* named by one of
    its own rules exactly as open as it is today
    (`authorize_if always()` — the same spec's Assumption 5, lines 65-66). A
    second, new read action invented here would not be one of the actions
    27w.2's rule 8 names, so once 27w.2 lands it falls into that unnamed,
    wide-open bucket instead — any caller could read every counting vote in
    any phase of any game through it, seat or no seat, which is exactly what
    27w.2 exists to prevent. Reusing the existing, already-named `:read`
    action closes that hole by construction: it is covered by 27w.2's rule 8
    either way. But rule 8 also means this reactor's own read of that same
    action now runs with no actor at all (`ResolveLynch` is background
    game-rule logic — see the reactor's own moduledoc precedent in
    `check_win.ex`, `resolve_win.ex` — never a request made on a player's
    behalf), so once 27w.2's policy is in effect, an authorized-by-default
    call would find no seat matching a nil actor and silently return zero
    votes for every phase — rules 1-4 would then always decide `:no_lynch`,
    in production, for every game, not just this bead's own tests. This is
    exactly the same shape of forced consequence 27w.2's own spec already
    documents and fixes for `CheckWin`'s unrelated `read :living_players`
    step (`docs/specs/werewolf_ash-27w.2.md`, lines 171-174: "that step needs
    `authorize?: false` ... this is not a free-standing production change, it
    is this rule reaching a real caller") — `authorize?: false` is a
    documented, valid option on `Ash.Reactor`'s `read` step
    (`deps/ash/documentation/dsls/DSL-Ash.Reactor.md:3351`,
    `deps/ash/lib/ash/reactor/builders/read.ex:24`). **No test in this
    bead's own suite can catch a missing `authorize?: false` here**. `Action`
    carries no `authorizers` at all until 27w.2 merges, so before that, the
    read behaves identically whether or not the flag is set — passing or
    failing this rule makes no test outcome differ, exactly the situation
    rule 16 above describes for `async?: false`, and for the same reason
    given there: the code-reviewer must verify this rule by reading the call
    site, not by running the suite.
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
- **Changing or withdrawing a vote while alive** (qss.21): letting a living
  player change their day vote to a different target, or withdraw it
  entirely, any time before voting closes, and the parallel change/withdraw
  behaviour for the bodyguard's protection. This bead only *counts* whatever
  `:vote` actions exist for the phase when `end_day` runs (rule 1) — it
  reads the current rows however they got there, filtered by rules 8 and 9;
  it does not add any way to change or delete a vote, and it does not touch
  `Action`'s `create :create` action, its `accept` list, or its
  `one_per_actor_per_phase_per_type` identity.
- **Target/actor validity** (qss.18): no check that a vote's target is
  alive at cast time, no cross-game actor/target/phase check, no
  consecutive-protect rule. This bead's rules 8-9 state what happens when a
  vote's actor or target is no longer alive by resolution time regardless of
  whether qss.18 has landed; once it has, a vote can no longer *name* an
  already-dead target at cast time, which makes rule 9 rarer (it then only
  covers a target who dies *after* being voted for) but does not make this
  bead's behaviour under it change.
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
  and actor handling; nothing here is exposed to or gated for a caller. Rule
  17's `authorize?: false` on the vote-loading read is not an exception to
  this: it adds no policy, no authorizer, and no actor-based check of any
  kind — it is the same "this is game-rule logic, not an access check"
  treatment `CheckWin`'s own read step and `DealRoles.deal/2`'s roster read
  already need once 27w.2 lands, kept here only so this bead's own reactor
  does not silently break in production the day that happens, regardless of
  which of the two beads merges first.
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
  `:village` (rules 6, 12, 13) — this bare-reactor test has no `Phase` rows
  to destroy (it never goes through `end_day`/`AdvancePhase`), so rule 14's
  own coverage lives in the new `Ash.Resource.Change`'s direct test and the
  end-to-end test below, not here; a tied vote kills nobody and still runs
  the win check (rules 3, 7, 12); a dropped vote from a since-dead voter and
  a dropped vote for a since-dead target (rules 8, 9 — see the two dedicated
  bullets below for the exact contract); an existing `:protect` action for
  the lynched player does not save them (rule 10); votes cast in an earlier
  phase of the same game are not counted when a different phase's id is
  given (rule 5). Rule 16's `async?: false` itself has no passing/failing
  test that distinguishes it (that rule explains why) — the code-reviewer
  checks it by reading the call site. The same is true of rule 17's
  `authorize?: false` on the vote-loading read: it makes no difference to
  any test in this bead's own suite (`Action` carries no authorizer until
  `27w.2` merges), so the code-reviewer verifies it by reading that read
  step's call site, not by running the suite.
- The new `Ash.Resource.Change` wired into `Game`'s `:end_day` action (name
  advisory) — direct unit test(s) on its own contract, staged the way
  `apply_kill_test.exs:12-25`'s `stage/3` helper stages `ApplyKill` (build a
  bare changeset, call the module's `change/3`, pull the lone hook off the
  changeset, invoke it by hand) rather than only exercising it indirectly
  through `end_day!`. This is where rule 14 gets its direct coverage: stage
  the changeset all the way through `AdvancePhase`'s own hook first (so the
  night `Phase` row genuinely exists, matching production order), then
  invoke this change's hook in a scenario that decides a winner, and assert
  that night `Phase` row no longer exists (`Games.get_phase/1` returns
  `{:error, %Ash.Error.Query.NotFound{}}` or equivalent for its id) while
  the day phase captured earlier is still there with `ended_at` set — and,
  separately, in a scenario that decides no winner, assert the night phase
  from `AdvancePhase` is left exactly as `AdvancePhase` created it (rule 15).
- End to end, through the code interface: cast votes with
  `Games.create_action!/4`, then `Games.end_day!/1,2` —
  - a plurality lynch that does not end the game: the target's `alive` is
    `false` afterward and the game is in `:night` (rules 6, 15);
  - a plurality lynch that removes the last living wolf: `Games.end_day!`
    returns a game with `state: :finished`, `winner: :village`; no `Phase`
    row for that game has `ended_at: nil`; and no `Phase` row for that game
    has `kind: :night` — `Games.list_phases!(query: [filter: [game_id:
    game.id]])` returns only the day phase(s) already recorded, the last of
    them closed (rules 6, 12, 13, 14).
- Rule 5: votes cast in a different day phase of the same game are not
  counted. Resolve one day phase while another day phase holds votes for a
  different target, and assert only the resolved phase's votes decide.
- Rule 8: a since-dead voter's vote is dropped, and dropping it can change
  the outcome, not just leave a losing vote uncounted. Set up two votes for
  target A and one for target B, then mark one of A's voters dead before
  running the reactor; assert the reactor decides `:no_lynch` (A's remaining
  count ties B's) rather than lynching A, and that neither player's `alive`
  changes.
- Rule 9: a since-dead target's vote is dropped entirely — it disappears
  from the tally rather than surviving as a harmless no-op. Use five
  distinct players: two voters cast for target C, a third, separate voter
  (not C, not one of C's own two voters) casts for target D, then mark C
  dead (by some means other than this reactor, e.g.
  `Games.update_player!(c, %{alive: false})`) before running the reactor —
  D's voter must stay alive and must not be C, or rule 8 would also drop
  D's one vote and the expected lynch would wrongly read as `:no_lynch`.
  Assert the reactor lynches D (the only target left in the tally, with one
  vote) rather than deciding `:no_lynch` or re-applying `alive: false` to
  C, and that C's `alive` was never touched by this run.
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
  alive afterward — `184-197` ("a different type in the same phase...") and
  `297-329` ("day/night path..."). Both need a second, opposing vote added
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
  - The step that loads the phase's `:vote` actions must exclude one whose
    actor is not currently alive and one whose target is not currently
    alive (rules 8, 9) before anything reaches `tally/1`, whose own contract
    (rule 1) does not change. **Do this with `Action`'s existing `:read`
    action, not a new one** (rule 17) — filtering across the `belongs_to
    :actor` and `belongs_to :target` relationships
    (`lib/werewolf_ash/games/action.ex:116-124`) in the query passed to that
    read (Ash's `expr/1` supports a relationship path this way, e.g. `filter
    expr(friends.first_name == "ted")`,
    `deps/ash/documentation/topics/security/policies.md:763`), or by loading
    the phase's votes plainly and filtering the list in Elixir before
    handing it to `tally/1` — either is fine, this part is advisory. Adding
    a second, differently-named read action is not: see rule 17 for why.
- `lib/werewolf_ash/games/game.ex:90-101` — the `:end_day` action gains a
  second `change`, appended after the existing `{AdvancePhase, to: :night}`.
  The precedent for chaining two independently-hooked `Ash.Resource.Change`
  modules on one action already exists on `:start`: `change DealRoles` then
  `change {AdvancePhase, to: :by_clock}` (`game.ex:86-87`), each registering
  its own `after_action` hook (`deal_roles.ex:21`, `advance_phase.ex:43-45`).
- A new module, likely under `lib/werewolf_ash/games/game/changes/`,
  implementing rules 1-17 together with `resolve_lynch.ex` above (rule 17
  specifically lives in the reactor's own vote-loading read step, not in
  this change module).
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
    - If there is a winner, rule 14 requires *destroying* the night phase
      `AdvancePhase` just opened, as part of the same hook — not closing it
      (owner decision 2026-09-13, card decision 3: the game's history must
      show no night phase at all when it ends at dusk). `Phase` already has
      a plain `:destroy` action (`defaults [:read, :destroy]`,
      `lib/werewolf_ash/games/phase.ex:21`) with no extra validations, so
      nothing on the resource itself needs to change; the domain
      (`lib/werewolf_ash/games.ex`) has no `define` exposing it yet, so the
      hook will need either a new `define :destroy_phase, action: :destroy`
      entry there or a direct `Ash.destroy!/2` call — either is fine, this
      is advisory. Locating the phase to destroy can use the same lookup
      `AdvancePhase`'s own `open_next_phase/4` already uses to find the
      phase *it* needs to close — `Ash.load!(game, [:current_phase, ...],
      opts)` on a freshly reloaded game (`advance_phase.ex:59-61`) — since by
      the time this hook runs, `AdvancePhase`'s hook has already closed the
      day phase and opened the night one, so `current_phase` now resolves to
      the night phase, not the day phase whose id this change captured
      earlier. Do not destroy the day phase itself, which `AdvancePhase`
      already closed correctly and which rule 14 requires to remain (with
      `ended_at` set, as it already is).
  - This is exactly why rule 15's regression holds: `AdvancePhase`'s own
    behaviour, and `advance_phase_test.exs`'s coverage of it (built via
    `Changeset.for_update` without ever calling `Ash.update!`, so no hook —
    from either change — ever runs), are untouched.
- `test/werewolf_ash/games/reactors/resolve_lynch_test.exs` (new).
- A new test file alongside `advance_phase_test.exs`/`apply_kill_test.exs`
  for the new change's own direct unit tests.
- `test/werewolf_ash/games_test.exs` — new end-to-end cases in "phase
  transitions" or a new describe block.
- `test/werewolf_ash/games/action_test.exs:187` and `:302` — fixes required,
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
- `test/werewolf_ash/games_test.exs:209,278,290,333` — the "phase
  transitions" describe block. Confirmed by
  `grep -n ":vote" test/werewolf_ash/games_test.exs`, whose only hits are in
  a separate "actions" describe block (lines 636-690) that creates its
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
- `test/werewolf_ash/games/action_test.exs:65,96,117,131,145,192,211,304,
  337` — every `end_day!` call in this file. Confirmed by
  `grep -n ":vote" test/werewolf_ash/games/action_test.exs` (hits: lines 52,
  54, 104, 116, 121, 174, 177, 187, 196, 302, 308): of those, only 174, 187
  and 302 cast a vote that is still standing (no later action on the same
  target/phase clears it) at the time some `end_day!` call in the same test
  runs — every other hit is either a bare assertion/description string (54,
  116) or a `:vote` creation the test itself expects to be rejected (104,
  121, 177, 308), and 196 casts a fresh vote in `day2`, after Break 1's own
  `end_day!`/`end_night!` calls, with no further `end_day!` call in that test
  to reach. **Two of those three are real breaks — line 187 was missed in an
  earlier revision of this spec and line 302's proposed fix in that revision
  was itself wrong; both are corrected below.** Line 174's vote
  (`p.villager.id -> p.werewolf.id`, inside "refuses a second action of the
  same type in the same phase (rule 9)", `action_test.exs:169-182`) is
  unaffected: that test never calls `end_day!` at all.

```
grep -n ":vote" test/werewolf_ash/games/action_test.exs
```

**Break 1: `test/werewolf_ash/games/action_test.exs:184-197`**, "a different
type in the same phase, or the same type in a later phase, still succeeds".
Line 187 casts `Games.create_action!(day.id, p.villager.id, p.werewolf.id,
:vote)` — a single vote naming the game's *only* werewolf (`started_game/0`,
`action_test.exs:18-31`, deals exactly 1 werewolf among 5 players). Line 192
calls `Games.end_day!(game, %{now: @dusk})`: under rules 1-2 that lone vote
is a plurality of one, so rule 6 lynches the werewolf, rule 12's win check
then sees 0 living wolves, and rule 13 finishes the game as `:village`
before night ever opens. Line 193, `Games.end_night!(game, %{now: @dawn})`,
then raises `NoMatchingTransition` — `end_night`'s `from: :night` (`game.ex:44`)
does not match a `:finished` game. **The test's expectation is stale**, not
the new rule: this test's own purpose (per its name) is that a different
action type, or the same type in a later phase, still succeeds — it needs
*some* vote to exist that day, not one that decides the game.

**Break 2: `test/werewolf_ash/games/action_test.exs:297-329`**, "day/night
path: bodyguard protects, a vote lands, a kill lands, the seer investigates".
Line 302 casts the same shape of vote (`p.villager.id -> p.werewolf.id`).
Line 304's `Games.end_day!` lynches the werewolf and finishes the game the
same way. `night = current_phase(game)` at line 305 then cannot return a
usable night phase (rule 14: no phase is left open), and even if it could,
line 311's `Games.create_kill_action!(night.id, p.werewolf.id, target.id)`
would raise — its actor is now dead, and `:kill`'s unconditional
`ActorAlive` validation (`action.ex:81`) rejects it. Stale for the same
reason as Break 1: the test's own purpose is to exercise the *night's* kill
and investigate flow, and it only needs *some* day-phase action to reach
night.

**The fix for both, and why simply retargeting the vote does not work:** an
earlier revision of this spec proposed retargeting line 302's vote to
`p.villager.id` instead of the werewolf. That is wrong: `p.villager` is the
*actor* of two later calls in the same test that each expect exactly one
error —
`assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
Games.create_action(night.id, p.villager.id, p.werewolf.id, :vote)`
(lines 307-308, rejected today only for being a `:vote` at night) and
`assert {:error, %Ash.Error.Invalid{errors: [%{field: :type}]}} =
Games.create_kill_action(night.id, p.villager.id, p.bodyguard.id)`
(lines 319-320, rejected today only for a non-werewolf actor). Ash
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
(line 193) and `day2`'s own fresh vote (line 196) then run exactly as they
do today. In Break 2, `night`'s kill, the seer's investigation, and the
three rejected-action assertions (lines 307-308, 319-320, 322-323) then run
exactly as they do today, since every actor and target they reference is
still alive.

No other file references `end_day`, `:vote`, or these reactors outside
what's listed above — confirmed by the two greps run above plus
`grep -rn "ResolveWin\|CheckWin" lib/ test/ --include="*.ex" --include="*.exs"`,
whose only hits are `reactors/check_win.ex`, `reactors/resolve_win.ex`, and
their own two test files (`check_win_test.exs`, `resolve_win_test.exs`),
none of which call `end_day`.

### Rule 14's revision (destroy, not close) breaks nothing existing

Revised 2026-09-13 for card decision 3 (skip opening night). This changes
only the new change's own hook, not `AdvancePhase`, so the question is
whether any already-merged test asserts the *old* rule 14 behaviour (a
closed, zero-length night `Phase` surviving a win at dusk). None does,
because no already-merged test reaches a win at dusk through `end_day` at
all — every path that does was already inventoried above and dead-ends
short of a win:

```
grep -n "kind: :night\|ended_at: nil" test/werewolf_ash/games_test.exs
```

Hits: `games_test.exs:204,216,219,229,234,251,349`. Six of the seven are
inside the "phase transitions" describe block already covered above (no
votes cast anywhere in it, so rules 1-4 always decide `:no_lynch` and rule
12's win check always sees 1-vs-4 living and stays `:continue` — see the
analysis under the first grep in this section), or, at line 251, a night
phase opened by `start_game!` landing directly in night by clock, which
never calls `end_day` at all. Read directly (not just grepped): the
`end_day!` call at `games_test.exs:209`, the only one in this file whose
surrounding assertions (`lines 213-221`) check a night phase's shape, is
inside that same no-lynch, no-winner scenario, so `AdvancePhase`'s night
phase is expected to survive untouched there — exactly rule 15's regression
guarantee, which this revision does not touch. The seventh, line 349
("rejects transitions that do not match the current state"), calls
`Games.end_day(game, %{now: now})` at line 333 while the game is still
`:lobby` (before `start_game!` has even run at line 338); that call is
rejected outright by the state machine (`NoMatchingTransition`) before any
of this bead's logic — new or old — ever runs, so it is unaffected either
way.

`action_test.exs`'s two fixed tests (Break 1 and Break 2, above) are the
only other place in the repo where a day-phase vote and an `end_day!` call
coexist, and the fix already required for them (an opposing vote, forcing a
tie) means neither one ever reaches rule 13 in the first place — confirmed
by reading both tests directly (`action_test.exs:184-197`, `:297-329`):
neither test's own assertions inspect a `Phase` row's `kind` or `ended_at`
after `end_day!` at all, only `current_phase(game)`'s use as an id source
for the next action. Rule 14's revision has nothing to break in either
file. No test anywhere else references `Phase` and `end_day` together
(confirmed by the `end_day\b` grep already run above, whose only test-file
hits are exactly these two files).
