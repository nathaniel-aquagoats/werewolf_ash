# werewolf_ash-qss.16: Vote visibility: who sees the day tally and when

Depends on: werewolf_ash-qss.5, werewolf_ash-27w.2

## For the owner

**What changes.** During the day, every player in the game — including those
who have already died — can watch the vote tally update live: who is voting
for whom, as it happens. Your own vote always shows up under your name, even
after you die. The wolves' night kill stays anonymous to everyone but the
wolves; only the day vote is open.

**Decisions for you.**
1. Open ballot vs. secret ballot (who sees who voted for whom, and when) —
   open (everyone watches votes land live) vs. secret (see only counts, or
   see nothing until the day resolves). **Recommended:** open ballot — the
   classic default, and what this spec builds.
2. Who sees the running tally during the day — living players only, or
   everyone in the game? **Recommended:** everyone; living and dead players
   see the identical tally.
3. What do dead players see — the same tally as the living, or something
   extra? **Recommended:** exactly the same as the living, nothing more.
4. When do votes become visible — the instant they're cast, or only once the
   day resolves? **Recommended:** instantly; the tally always reflects
   whatever votes exist right now.

**Rule changes.** Adds to CLAUDE.md's settled decisions: "the day vote is an
open ballot: every game member, living or dead, sees the full running
tally — who voted for whom — visible the instant each vote is cast; the
wolves' night kill is never shown to non-wolves."

## Goal

Today a day's votes can be cast (qss.4) and, once qss.5 lands, resolved into a
lynch or no-lynch at `end_day` — but nothing in between lets a caller ask
"what does today's vote look like right now." After this bead,
`WerewolfAsh.Games.Phase` can answer that directly: a `:vote_tally`
calculation returns, for a given phase, the same map from target player id to
voter player ids that `WerewolfAsh.Games.Reactors.ResolveLynch.tally/1`
(qss.5) computes — but only over the `:vote` rows the reading actor is
actually allowed to see. Because 27w.2's `Action` read policy (rule 8) already
grants every game member — any role, living or dead — unrestricted read
access to `:vote` rows, and separately protects `:kill`/`:investigate` rows,
the visibility this bead needs comes from the calculation re-running an
ordinary, fully authorized read of `Action` itself — rather than from any new
authorization code, and, importantly, *not* from declaring the phase's
`actions` relationship as a load dependency (verified broken for this
purpose in this Ash version — see rule 1): a game member sees the whole
day's tally including their own vote; someone outside the game sees nothing;
a night phase's kill never surfaces through this path at all. The ballot
style — full transparency, the epic's classic open-vote default — is decided
and recorded here, as the bead's `Done:` line asks.

## Assumptions

1. **Open ballot, not secret.** Per the bead's own default, this spec builds
   full transparency: every game member sees the running tally — every
   target's vote count and the identity of every player who voted for them —
   with no narrower "counts only" or "nothing until resolution" mode. This is
   recorded as the settled decision in the new calculation module's
   `@moduledoc` (see rule 1 and Touches), because the coder cannot record it
   in `CLAUDE.md` directly: `protect-pipeline.py` refuses subagent writes to
   that file, and the bead pipeline's own division of labour reserves
   `CLAUDE.md` edits for the main tree. After this bead merges, the
   coordinator adds the decision to `CLAUDE.md`'s "Rules decisions already made"
   list in the main tree (recorded on the bead's notes); this spec does not
   perform that step.
   If the owner reverses this to a secret ballot later, rules 1, 4 and 6 below
   are the ones that redesign would replace, and 27w.2's rule 8 (which
   currently grants `:vote` rows no narrowing beyond game membership) would
   need to change too — see the note on 27w.2 below.

2. **This spec adds no authorization code of its own; its visibility rules
   depend on werewolf_ash-27w.2.** Rules 4, 5 and 6 hold because rule 1's
   calculation performs its own authorized read of `Action`, which applies
   `Action`'s read policy from 27w.2 (rule 8). `qss.16` depends on `27w.2` in
   the bead graph, so that policy exists before this bead is implemented, and
   the non-member tests below exercise real filtering. This spec adds no
   redundant membership check, per the brief not to add a second policy layer.

3. **A calculation, not a preparation.** The bead's own acceptance criteria
   say "a preparation or calculation." A preparation (like
   `Message.Preparations.VisibleTo`) narrows which *rows* a read returns; this
   bead needs one aggregated map value per phase, which is a `calculation`'s
   job, not a preparation's. `Phase` gains a `:vote_tally` calculation (see
   rule 1) rather than a new read action.

## Rules

1. `WerewolfAsh.Games.Phase` gains a `:vote_tally` calculation, of type
   `:map`, backed by a new `Ash.Resource.Calculation` module (name advisory,
   see Touches). Reading it for a given phase — e.g.
   `Games.get_phase!(phase.id, load: :vote_tally, actor: actor)` — returns
   exactly `WerewolfAsh.Games.Reactors.ResolveLynch.tally/1`'s result (the
   qss.5 function, reused verbatim: same module, same arity, same output
   shape — do not fork or reshape it) computed over the `:vote`-type `Action`
   rows of that phase **that the calling actor is authorized to read**.
   Nothing in this calculation re-checks game membership, role or aliveness
   itself: visibility is entirely inherited from `Action`'s own read policy
   (27w.2 rule 8), by having the calculation's `calculate/3` callback
   (`deps/ash/lib/ash/resource/calculation/calculation.ex:212`) perform its
   *own* ordinary, top-level, authorized read of `Action` — filtered to the
   phases being calculated and `type == :vote` — passing
   `Ash.Context.to_opts(context)` (with no overrides) as that read's options,
   so the calculation's own `actor` and `authorize?` (inherited unchanged
   from whatever query asked for `:vote_tally`) govern it exactly as they
   would `Games.list_actions`.

   **This bead's calculation must NOT declare the phase's `actions`
   relationship as a `load/3` dependency instead** (e.g.
   `def load(_query, _opts, _context), do: [:actions]`) — that looks
   equivalent and is the natural thing to reach for, but it is verified
   broken for this purpose in this version of Ash: a relationship declared as
   a calculation's load dependency is authorized with `authorize?: false`
   regardless of the caller's own actor/authorize?, so it would silently hand
   every phase's `:vote` (and `:kill`/`:investigate`) rows to every caller,
   member or not. This is deliberate elsewhere in Ash, not a bug to work
   around, but it means the naive design is actively wrong here, not merely
   non-preferred:
   - When a calculation's load requirement is a relationship and the
     enclosing query is itself authorized, the relationship branch of
     `split_and_load_calculations/6` calls `add_new_relationship_calc/11`
     (`deps/ash/lib/ash/actions/read/calculations.ex:1649-1690`), which
     builds a hidden `{:__calc_dep__, ...}` calculation backed by
     `Ash.Resource.Calculation.LoadRelationship` with **`opts: [authorize?:
     false]` hardcoded** at the call site (`calculations.ex:1690`). A nearby
     comment (`calculations.ex:927-930`) acknowledges relationship-load
     dependencies of a calculation are not policy-checked the way the rest
     of a query is.
   - `LoadRelationship.calculate/3`
     (`deps/ash/lib/ash/resource/calculation/load_relationship.ex:41-47`)
     turns that into `Ash.Context.to_opts(context, Keyword.put(opts[:opts]
     || [], :domain, ...))` — i.e. it calls `to_opts/2` **with**
     `authorize?: false` as an explicit override — before making its own
     `Ash.load/3` call.
   - `Ash.Scope.to_opts/2` (`deps/ash/lib/ash/scope.ex:107-122`) builds its
     base keyword list from the context (actor, tenant, `authorize?`, ...)
     and then does `Keyword.merge(overrides)` (line 122) — the override
     wins. So the relationship load keeps the caller's actor attached but
     forces `authorize?` to `false`, meaning every `Action` row of the phase
     loads regardless of 27w.2's policy — rule 5 below would fail, and the
     tempting "fix" would be to loosen rule 5, not the design.
   - An explicit read performed directly inside `calculate/3`, by contrast,
     is an ordinary top-level `Ash.read` on `Action`, never routed through
     `LoadRelationship`, so it is authorized the normal way
     (`deps/ash/lib/ash/actions/helpers.ex:394-395`'s `:by_default` default
     still applies: `authorize?` defaults to `true` unless explicitly
     disabled, and neither `WerewolfAsh.Games` nor `WerewolfAsh.Accounts`
     overrides that domain setting). Passing it `Ash.Context.to_opts(context)`
     with **no** override carries the calculation's actual `actor` and
     `authorize?` through unchanged — confirmed by `Ash.Scope.ToOpts`'s
     implementation for `Ash.Resource.Calculation.Context`
     (`deps/ash/lib/ash/scope.ex:164-186`), whose `get_actor/1` and
     `get_authorize?/1` read straight off the context struct Ash already
     built for this calculation from the enclosing query. This is what makes
     rules 4 and 5 below actually true, not just true in the cases a test
     happens to try.
   - This calculation needs no `load/3` override at all: the default,
     no-op `load/3` that `use Ash.Resource.Calculation` already provides
     (`deps/ash/lib/ash/resource/calculation/calculation.ex:181`, returning
     `[]`) is correct here precisely because declaring a relationship
     dependency is the thing to avoid.
2. The calculation's own read (rule 1) is filtered to `Action` rows with
   `type == :vote` belonging to the phase being read. A day phase can carry
   `:protect` rows alongside `:vote` rows (`action.ex`'s
   `TypeRequiresPhaseAndRole, phase_kind: :day` validation applies to both
   `:vote` and, with `role: :bodyguard`, `:protect`); those, and any
   `:kill`/`:investigate`/`:shoot` rows recorded elsewhere, never reach
   `tally/1` because the query itself excludes them. This filtering is a
   `type` clause in the query, not a check on the reading actor's role — it
   holds identically no matter who is asking.
3. Because `:vote` actions can only ever be recorded on a `:day`-kind phase
   (the same `action.ex` validation cited in rule 2 — no code path creates a
   `:vote` row on a night or `hunter_pending` phase), reading `:vote_tally`
   for a non-day phase always returns `%{}`. This is a corollary of rule 2
   plus that existing validation, not a new phase-kind check to add.
4. A game member — any role, living or dead, per 27w.2 rule 8's baseline
   ("an actor may read an `Action` row only while they hold a seat — any
   role, alive or dead — in that row's phase's game") — reading `:vote_tally`
   for a day phase of their own game sees every vote cast in that phase: the
   full map from target id to voter ids, unfiltered by any voter's or
   target's own role or aliveness.
5. An actor with no seat in the phase's game — including no actor at all —
   reading `:vote_tally` gets `%{}` back, never a hard authorization error.
   This is `ResolveLynch.tally/1`'s own empty-input case (qss.5 rule 4)
   reached because 27w.2 rule 8's baseline filters the underlying `:vote`
   rows to nothing before the tally is computed — the same
   "policies filter reads to empty, they don't raise" pattern already used
   for `Game`, `Player` and `Action` reads elsewhere (27w.2 rules 1, 4, 8).
6. A player who cast a vote in the tallied phase always finds their own
   player id among the voters for the target they chose, when they themselves
   read that phase's `:vote_tally` — including when that player has since
   died (qss.5's own A1 assumption: a since-dead voter's vote still counts).
   This is a corollary of rule 4 under the open-ballot design chosen here, but
   it is kept as its own rule so a future narrowing of rule 4 (e.g. a secret
   ballot) cannot silently drop it without a test noticing.
7. (withdrawn — no code in this bead can break it: it would only check that
   qss.5's `end_day` doesn't delete `:vote` rows. See Out of scope.)
8. The `:vote_tally` calculation is declared `public? true`, so a later
   GraphQL field (27w.3) can select it without any further domain-layer
   change — this is what "expose the tally as data the API can serve" means
   concretely for this bead, which stops at the domain code interface.

## Out of scope

- **Secret ballot** (counts-only, or nothing until resolution): not built.
  Recorded only as the alternative this spec did not choose (Assumption 1).
- **Updating `CLAUDE.md`'s settled-decisions list**: the coder cannot touch
  that file (`protect-pipeline.py`); the coordinator records it in the main
  tree after this bead merges (Assumption 1).
- **Any policy or authorizer on `Phase`**: not added here. `Phase` stays
  exactly as open as 27w.2 explicitly left it; this bead's visibility comes
  entirely from `Action`'s policy via the explicit read in rule 1, not from
  gating `Phase` itself. Fetching a bare `Phase` row's `kind`/`number` (with
  no `:vote_tally` load) remains unauthenticated exactly as it is today —
  unchanged, pre-existing, and not this bead's problem to fix.
- **Implementing `:vote_tally` via a `load/3` relationship dependency**
  (e.g. `def load(_query, _opts, _context), do: [:actions]`, then filtering
  the preloaded association inside `calculate/3`): this is the design this
  spec originally proposed and it is wrong, not just unpreferred — verified
  in rule 1's citations to always run that relationship load with
  `authorize?: false`, regardless of the caller's own actor/authorize?,
  which would hand every phase's votes to every caller including a
  non-member or an anonymous one. Rule 1's explicit, self-authorized read
  inside `calculate/3` is required instead, and needs no `load/3` override
  at all.
- **Any change to `Action`'s policies, or to 27w.2 rule 8 itself**: this bead
  depends on that policy but does not implement, extend, or duplicate it — no
  second policy layer, per the brief.
- **The tally surviving `end_day`**: qss.5's resolution doesn't delete or change
  `:vote` rows, so the tally reads the same after the day closes. That is qss.5's
  behaviour, not something this bead implements or could break (formerly rule 7).
- **Any change to `WerewolfAsh.Games.Reactors.ResolveLynch`** (qss.5),
  including its moduledoc: reused exactly as qss.5 defines it.
- **A `player_id`/"viewer" argument on a new read action**, mirroring
  `Message.visible_to`'s pattern: deliberately not built. That pattern exists
  on `Message` because its filter needs to know *which* player's view to
  compute and had to be paired with a caller-identity policy (27w.2 rule 10)
  to stop a caller from asking for someone else's view. This bead's
  visibility is keyed off the ambient actor of the call, not a
  caller-supplied argument, so there is no id to spoof and no matching policy
  to write — adding one here would be inventing both a new argument and the
  second policy layer the brief forbids.
- **The night's kill "who did it" reveal, or any wolf-side kill tally**: per
  27w.2 Assumption 3, the pack's night action is a single `:kill` row, not a
  set of ballots to tally — there is no wolf-side tally for this bead to
  build, and rules 2–3 only guarantee a `:kill` row never leaks through the
  day-vote path.
- **Announcing the lynch result, or a dusk notice** (qss.19): no chat message,
  no feed event, no `Phase.summary` write.
- **Moving vote closing earlier** (qss.15): `:vote_tally` reads whatever
  `:vote` rows exist at the moment it's read, with no deadline or clock
  dependency of its own; when voting "closes" is unaffected by this bead.
- **GraphQL/API exposure** (27w.3): rule 8 only makes the calculation
  selectable by a future GraphQL field; no schema, query, or mutation is
  added here.
- **The mobile game-screen tally UI** (o25.5): out of scope for any domain
  bead.
- **Any database migration**: a calculation is computed, not persisted; this
  bead adds no resource attribute, so `mix ash.codegen` has nothing new to
  generate.

## Acceptance

- The new calculation module (name advisory, e.g.
  `WerewolfAsh.Games.Phase.Calculations.VoteTally`) — direct unit tests on its
  `calculate/3` callback (`deps/ash/lib/ash/resource/calculation/calculation.ex:212`),
  using real, persisted `Phase`/`Action`/`Player` rows and a real actor rather
  than preloaded in-memory structs: the whole point of rule 1's design is
  that the calculation performs its own authorized read, so a test that
  hands `calculate/3` an already-populated struct would never exercise that
  read at all, and would pass identically whether the read was authorized or
  not. A day phase seeded with both `:vote` and `:protect` rows, called with
  an actor holding a seat in that game, tallies only the `:vote` rows in
  `ResolveLynch.tally/1`'s exact shape (rules 1, 2); the identical phase
  called with an actor holding no seat in the game returns `%{}` (rules 1,
  5) — this is the specific case that the original, load/3-based design
  would have failed, so the test must construct a genuine non-member actor
  and assert `%{}`, not merely assert against a member and stop; a phase
  with no `:vote` rows recorded at all (a night phase's `:kill` row, or a day
  phase before any vote is cast) returns `%{}` for a member too (rules 2, 3,
  and qss.5 rule 4's empty case). No test is needed for a `load/3` contract:
  this calculation declares no relationship dependency (rule 1) and relies
  on the default, no-op `load/3` that `use Ash.Resource.Calculation` already
  provides (`deps/ash/lib/ash/resource/calculation/calculation.ex:181`).
  When a test calls `calculate/3` directly and builds its own
  `Ash.Resource.Calculation.Context`, it must set `authorize?: true`, or leave it
  `nil`, which defaults to `true`, alongside the non-member actor. A context with
  `authorize?: false` would hand the member-only tally to everyone and hide exactly
  the leak rule 1 exists to prevent.
- `WerewolfAsh.Games.get_phase/1,2` (or `list_phases/0,1`) with
  `load: :vote_tally` — direct tests through the code interface, each
  supplying a distinct `actor`: a living game member sees the full tally
  (rule 4); a dead game member sees the identical full tally, including a
  vote they cast before dying (rules 4, 6); an actor holding no seat in the
  game, and a call with no actor at all, both return `%{}` (rule 5); the
  acting player's own vote is present among the voters for their chosen
  target (rule 6); reading `:vote_tally` on the game's current night phase
  (seeded with a `:kill` row) returns `%{}` and the response never contains
  the kill's actor or target under any key (rules 2, 3).
- `Ash.Resource.Info.public_calculation(WerewolfAsh.Games.Phase, :vote_tally)`
  (`deps/ash/lib/ash/resource/info.ex:582-588`) — direct test: returns the
  calculation, not `nil` (rule 8).
- End to end, through the code interface: start a five-plus-player game, cast
  two or more `:vote` actions from different actors in the open day phase,
  then compare `Games.get_phase!(day.id, load: :vote_tally, actor: <a game
  member>)`'s result against `ResolveLynch.tally/1` computed directly over
  the same phase's `:vote` actions fetched with `authorize?: false` — the two
  must be identical, proving the calculation reuses qss.5's tally rather than
  recomputing a different one (rule 1).

### Existing tests this will break

This bead adds a new calculation to `Phase` and a new module; it changes no
existing action, attribute, relationship or policy. Grepped for every way
that could still land on an existing test:

```
grep -rn "vote_tally" lib/ test/ --include="*.ex" --include="*.exs"
```
No hits — the name is new, nothing collides with it.

```
grep -rn "ResolveLynch" lib/ test/ --include="*.ex" --include="*.exs"
```
No hits in this repository as of this writing (qss.5 has not merged yet); by
the time this bead is coded qss.5 will exist per the pipeline's dependency
order, and this bead does not modify `tally/1` or any of qss.5's own tests.

```
grep -rn "load: :actions\|load: \[:actions\]" test/ --include="*.exs"
```
One hit: `test/werewolf_ash/games_test.exs:566`
(`Games.get_phase!(ctx.phase.id, load: :actions).actions`). This is already
listed in 27w.2's own "Existing tests this will break" section as needing
`authorize?: false` for 27w.2 rule 8's baseline — it loads the raw `.actions`
association, not this bead's new `:vote_tally` calculation, so it is
unaffected by anything in this spec and needs no further change here.

```
grep -rn "== %Phase{" test/ --include="*.exs"
```
No hits — no test asserts full-struct equality on a `Phase` that a new
struct field (the calculation, `field?: true` by default) could break.

```
grep -rln "Games.Phase\b" test/ --include="*.exs"
```
One hit: `test/werewolf_ash/games/enum_docs_test.exs`. Read directly: it
iterates a fixed list of *enum type* modules (including `Phase.Kind`,
`Player.Role`, `Message.Channel`, `Action.Type`) and asserts each has a
non-empty `@moduledoc` — it never touches the `Phase` resource or its
calculations. Unaffected.

No other existing test file references `Phase`'s calculations, the phrase
"vote_tally", or `ResolveLynch` — nothing else to fix.

## Touches

Advisory only.

- `lib/werewolf_ash/games/phase.ex` — a `calculations do calculate
  :vote_tally, :map, {Module, []}, public?: true end` block (exact DSL call
  form is implementation, not a rule).
- `lib/werewolf_ash/games/phase/calculations/vote_tally.ex` (new) —
  implements only `calculate/3` (rule 1): one authorized read of
  `WerewolfAsh.Games.Action` per batch, filtered to `phase_id in <the
  batch's phase ids> and type == :vote`, passing
  `Ash.Context.to_opts(context)` unchanged as that read's options; group the
  results by `phase_id`; pass each phase's group to
  `WerewolfAsh.Games.Reactors.ResolveLynch.tally/1`. Does not override
  `load/3` — the default no-op `use Ash.Resource.Calculation` already
  provides is correct here precisely because this calculation must not
  declare a relationship dependency (rule 1). Its `@moduledoc` is where
  Assumption 1's open-ballot decision gets recorded, since the coder cannot
  write it to `CLAUDE.md`.
- No changes to `lib/werewolf_ash/games/action.ex`, `player.ex`, `game.ex`,
  `message.ex`, or any policy/authorizer/field-policy code — this bead
  touches only `Phase` and the new calculation module.
- No changes to `lib/werewolf_ash/games.ex` — `get_phase`/`list_phases`
  already accept arbitrary `load:`/`actor:` options as any Ash code interface
  read does; no new `define` is needed to reach `:vote_tally`.
- `test/werewolf_ash/games/phase/calculations/vote_tally_test.exs` (new) —
  the calculation module's own direct unit tests.
- `test/werewolf_ash/games_test.exs` — a new describe block (e.g. "vote
  tally") for the policy-delegation and end-to-end cases, alongside the
  existing "phase transitions"/"actions" blocks. Do not fold these into
  qss.5's own `resolve_lynch_test.exs` — that file is qss.5's, testing
  `tally/1`/`decide/1`/the reactor, not this bead's calculation.
