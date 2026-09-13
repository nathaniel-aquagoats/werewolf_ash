# werewolf_ash-qss.16: Vote visibility: who sees the day tally and when

Depends on: werewolf_ash-qss.5, werewolf_ash-27w.2

## For the owner

**What changes.** During the day, every player in the game can watch the
vote tally update live: who is voting for whom, as it happens. A living
player sees only the votes that will actually decide the day — a living
voter's current vote for a still-living target — with one exception: your
own vote stays visible to you even after it stops counting because your
target died, now marked as not counting, so you know to cast another; no
other living player sees a vote once it stops counting, including yours.
That view updates instantly whenever a vote is cast, changed, withdrawn, or
stops counting. A dead player sees more: every vote still on the books,
including ones that no longer count because the voter or their target has
since died, each clearly marked as not counting — the dead watch as
spectators with the full picture, the living see only what's live (plus
their own). The wolves' night kill is never shown to living non-wolves, and
never surfaces through the tally either way; only the day vote is open.

**Decisions for you.**
1. Open ballot vs. secret ballot (who sees who voted for whom, and when) —
   open (everyone watches votes land live) vs. secret (see only counts, or
   see nothing until the day resolves). **Decided:** open ballot — everyone
   in the game sees who is voting for whom, live, counting only the votes
   that will count.
2. Who sees the running tally during the day — living players only, or
   everyone in the game? **Decided:** everyone in the game, living or dead,
   sees the tally.
3. What do dead players see — the same tally as the living, or something
   extra? **Decided:** dead players see every vote, with non-counting votes
   marked; the living see counting votes only.
4. When do votes become visible — the instant they're cast, or only once the
   day resolves? **Decided:** instantly; the tally updates the moment a vote
   is cast, changed, or withdrawn.
5. Which votes does the live tally show? — **Decided:** only votes that will
   count: living voters' current votes for living targets. A vote from a
   player who has since died, or naming a target who has since died, is not
   shown, and a change or withdrawal shows the instant it happens.
6. Your vote stops counting because your target died — do you still see it?
   — **Decided:** yes, marked not counting; other living players don't see
   it.

**Rule changes.** Adds to CLAUDE.md's settled decisions: "the day vote is an
open ballot, watched live and updated instantly. A living game member sees
only the votes that currently count — each living voter's current vote for a
living target — plus their own vote even after it stops counting, marked as
such, visible to no other living player. A dead game member sees every
currently cast vote in the phase, including one from a since-dead voter or
naming a since-dead target, each marked whether it currently counts — the
dead see everything, as spectators in an afterlife. The wolves' night kill is
never shown to living non-wolves, and never surfaces through the tally."

## Goal

Today a day's votes can be cast (qss.4) and, once qss.5 lands, resolved into a
lynch or no-lynch at `end_day` — but nothing in between lets a caller ask
"what does today's vote look like right now." After this bead,
`WerewolfAsh.Games.Phase` answers that directly, in one uniform shape for
every reader: a `:vote_tally` calculation returns a map from target player id
to a list of vote-detail maps, `%{voter_id: <player id>, counts: <boolean>}`
— one entry per `:vote` row currently recorded in that phase. `counts` on
each entry is `true` exactly when that entry's voter *and* target are both
currently alive — the identical living-voter/living-target rule qss.5 applies
at its own resolution (qss.5 rules 8-9) — decided by filtering the phase's
`:vote` rows to a living voter and a living target and handing the survivors
to `WerewolfAsh.Games.Reactors.ResolveLynch.tally/1` (qss.5) to group them.
`tally/1` itself is unchanged and has no idea what "alive" means (it just
groups whatever list of `:vote` structs it's handed), so this bead's own
calculation does that filtering itself, mirroring
(not reusing) the identical living-voter/living-target filter qss.5's own
`ResolveLynch` reactor applies, separately, before its own call to that same
`tally/1`. Which of these uniformly-shaped entries a given reader actually
gets back is where the two audiences differ: a living game member sees the
`counts: true` entries, plus their own entry even when it is `counts: false`
(owner decision 2026-09-13: your own vote keeps showing once it stops
counting, so you know to cast another — visible to you and no other living
reader) — dropping a target with no entries left under this narrowing
entirely — while a dead game member sees every entry, `counts: true` and
`counts: false` alike, the fuller picture (owner decision 2026-09-13, "the
dead see everything, as spectators in an afterlife"). Both views are built
from one single read of the `:vote`-type `Action` rows the reading actor is
actually allowed to see. Because 27w.2's `Action` read policy (rule 8)
already grants every game member — any role, living or dead — unrestricted
read access to `:vote` rows, and separately protects
`:kill`/`:investigate`/`:protect` rows, the visibility this bead needs comes
from the calculation re-running an ordinary, fully authorized read of `Action` itself
— rather than from any new authorization code, and, importantly, *not* from
declaring the phase's `actions` relationship as a load dependency (verified
broken for this purpose in this Ash version — see rule 1): which entries a
given actor's read keeps is decided separately, by their own `Player.alive`
in that game (rule 10) — not by anything about the votes themselves; someone
outside the game sees nothing either way; a night phase's kill never surfaces
through this path at all. The ballot style — full transparency, the epic's
classic open-vote default, now split into a living view of only the votes
that currently count and a dead view of everything currently on the books,
both expressed in the same shape — is decided and recorded here, as the
bead's `Done:` line asks.

## Assumptions

1. **Open ballot, not secret.** Per the owner's decision (the bead's own
   default, now confirmed), this spec builds full transparency, not a
   narrower "counts only" or "nothing until resolution" mode: a living game
   member sees every live target's vote count and the identity of every
   living voter who currently votes for them (rule 4's filtered view), and a
   dead game member sees the identity of every voter for every target,
   whether or not that vote currently counts (rule 9's unfiltered view). This
   is orthogonal to the owner's separate
   2026-09-13 decisions that (a) only living voters' votes for living targets
   count in the first place, and (b) which of those two views — living or
   dead — a reader gets depends on their own seat: those decisions narrow
   *which votes exist to be tallied, and for whom*, not how openly a vote is
   shown to the audience that can see it at all. This is recorded as the
   settled decision in the new calculation module's `@moduledoc` (see rule 1
   and Touches), because the coder cannot record it in `CLAUDE.md` directly:
   `protect-pipeline.py` refuses subagent writes to that file, and the bead
   pipeline's own division of labour reserves `CLAUDE.md` edits for the main
   tree. After this bead merges, the coordinator adds the decision to
   `CLAUDE.md`'s "Rules decisions already made" list in the main tree
   (recorded on the bead's notes); this spec does not perform that step.
   If the owner reverses this to a secret ballot later, rules 1, 4, 6, 9 and
   10 below are the ones that redesign would replace, and 27w.2's rule 8
   (which currently grants `:vote` rows no narrowing beyond game membership)
   would need to change too — see the note on 27w.2 below.

2. **This spec adds no *authorization* code of its own — no change to *who*
   may read anything — but it does add its own content filtering on top of
   an unfiltered read; those are different things.** Which `:vote` rows this
   bead's calculation is even handed comes entirely from `Action`'s own read
   policy (27w.2 rule 8), via rule 1's calculation performing its own
   authorized read; `qss.16` depends on `27w.2` in the bead graph, so that
   policy exists before this bead is implemented, and the non-member tests
   below exercise real filtering. This spec adds no redundant *membership*
   check, per the brief not to add a second policy layer. It does add two
   pieces of its own logic on top of that read, neither of which is
   authorization: (a) rule 4's filter of those rows to a living voter and a
   living target, before calling `tally/1` — `tally/1` (qss.5) does not do
   this itself (see rule 1) — mirroring, not reusing, the identical filter
   qss.5's own `ResolveLynch` reactor applies for its own purpose; and (b)
   rule 10's read of the reading actor's own `Player.alive` in the phase's
   game, to choose which of rule 1's uniformly-shaped entries a reader
   actually gets back — all of them (rule 9), or the `counts: true` ones plus
   the reader's own entry regardless of its `counts` (rule 4). Neither (a)
   nor (b) changes *whether* the actor may read
   `:vote_tally` at all (rule 5 still governs that) — (a) decides each
   entry's own `counts` flag, and (b) decides which of those already-built
   entries a given reader is shown.

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
   one uniform shape for every reader: a map from target id to a list of
   vote-detail maps, `%{voter_id: <player id>, counts: <boolean>}` — one
   entry per `:vote`-type `Action` row of that phase **that the calling actor
   is authorized to read**. `counts` on each entry is `true` exactly when
   that entry's voter and target are both currently alive, and `false`
   otherwise — the identical living-voter/living-target rule qss.5 applies at
   its own resolution (qss.5 rules 8-9), computed here by this bead's own
   calculation rather than inherited from qss.5. This bead's own calculation
   decides the flag by filtering the read rows to a living voter and a living
   target and handing the survivors to
   `WerewolfAsh.Games.Reactors.ResolveLynch.tally/1` (the qss.5 function,
   reused unmodified — same module, same arity, same input/output contract,
   not forked or reshaped itself), then marking every row by whether it
   appears in that result. `tally/1` itself has no notion of aliveness at all
   — it is qss.5's unchanged, pure grouping function, handed whatever list
   it's given — so this filtering is *this bead's own* code, mirroring (not
   reusing) the identical filter qss.5's `ResolveLynch` reactor applies,
   separately, before its own call to that same `tally/1` for its own purpose
   (deciding the lynch). Which *subset* of these uniformly-shaped entries a
   given reader actually gets back — every entry (a dead reader, rule 9), or
   the `counts: true` ones plus the reader's own entry regardless of its
   `counts` (a living reader, rule 4) — is decided by rule 10, by the
   reader's own seat, not by rule 1 itself. Nothing in this
   calculation re-checks game membership, role or aliveness *to decide which
   rows it is allowed to read*: visibility of the underlying rows is entirely
   inherited from `Action`'s own read policy (27w.2 rule 8), by having the
   calculation's `calculate/3` callback
   (`deps/ash/lib/ash/resource/calculation/calculation.ex:212`) perform its
   *own* ordinary, top-level, authorized read of `Action` — filtered to the
   phases being calculated and `type == :vote` — passing
   `Ash.Context.to_opts(context)` (with no overrides) as that read's options,
   so the calculation's own `actor` and `authorize?` (inherited unchanged
   from whatever query asked for `:vote_tally`) govern it exactly as they
   would `Games.list_actions`. What this calculation *does* check itself,
   after that read, is the aliveness of each row's voter and target (to build
   the `counts` flag) and the reading actor's own aliveness (rule 10, to pick
   which entries to keep) — neither is a read-authorization check; see
   Assumption 2.

   **This bead's calculation must NOT declare the phase's `actions`
   relationship as a `load/3` dependency instead** (e.g.
   `def load(_query, _opts, _context), do: [:actions]`) — that looks
   equivalent and is the natural thing to reach for, but it is verified
   broken for this purpose in this version of Ash: a relationship declared as
   a calculation's load dependency is authorized with `authorize?: false`
   regardless of the caller's own actor/authorize?, so it would silently hand
   every phase's `:vote` (and `:kill`/`:investigate`/`:protect`) rows to every caller,
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
4. A **living** game member (per 27w.2 rule 8's baseline that any seat —
   any role, alive or dead — may read `Action` rows in its own game) reading
   `:vote_tally` for a day phase of their own game gets back rule 1's
   uniform map, narrowed to: every entry whose `counts` is `true`, plus —
   when the reading actor themselves cast a `:vote` in that phase — their own
   entry (`voter_id` equal to the reader's own player id) under whichever
   target they chose, even when that entry's `counts` is `false` (owner
   decision 2026-09-13: a living voter keeps seeing their own vote once it
   stops counting, so they know to cast another; see card decision 6). No
   other player's `counts: false` entry is ever included in a living reader's
   view — the reader's-own-vote exception is keyed to the reader's own
   identity, not to the vote itself, so a different living reader looking at
   the same phase never sees it. A target left with no entry at all under
   this narrowing — no `counts: true` entry, and not the reader's own
   non-counting one either — is absent from the map entirely, as a key, not
   present with an empty list — matching `tally/1`'s own "a target nobody
   voted for is absent, not an empty list" contract (qss.5 rule 1) once
   translated through the entry shape. The `counts: true` narrowing is *this
   bead's own* filter, built by handing the rows whose voter and target are
   both alive to `tally/1` (rule 1) and keeping only the entries that match;
   `tally/1` itself is qss.5's unchanged, aliveness-agnostic grouping function
   and performs neither this restriction nor the reader's-own-vote exception,
   both of which are this bead's alone. The `counts: true` filter mirrors,
   rather than reuses, the identical living-voter/living-target rule qss.5's
   own `ResolveLynch` reactor applies before its own, separate call to
   `tally/1`, so the two never define "counts" differently. A **dead** game
   member reading the same phase gets rule 9's unfiltered view of the very
   same entries instead — never this rule's narrowed subset (owner decision
   2026-09-13); which of the two a given reader gets is decided by rule 10,
   not by anything about the votes themselves.
5. An actor with no seat in the phase's game — including no actor at all —
   reading `:vote_tally` gets `%{}` back, never a hard authorization error.
   This is `ResolveLynch.tally/1`'s own empty-input case (qss.5 rule 4)
   reached because 27w.2 rule 8's baseline filters the underlying `:vote`
   rows to nothing before the tally is computed — the same
   "policies filter reads to empty, they don't raise" pattern already used
   for `Game`, `Player` and `Action` reads elsewhere (27w.2 rules 1, 4, 8).
6. A player's own current vote, if they cast one in the tallied phase, has
   an entry in rule 1's uniform map (`%{voter_id: <own id>, counts:
   <boolean>}`, under whichever target they chose), and a living player
   always finds that entry when they read `:vote_tally` themselves, whatever
   its `counts` value: while their chosen target is alive, it's `counts:
   true` and appears in rule 4's view the same way it would to any other
   living reader; once their target dies, it becomes `counts: false` and
   rule 4's own-vote exception is what keeps it in *their* view — a different
   living reader looking at the same phase never sees that entry once it
   stops counting (owner decision 2026-09-13, card decision 6: seeing your
   own vote is what tells you to cast another). Once the player themselves
   has died, rule 10 gives them rule 9's unfiltered view instead, where their
   own entry always appears under whichever target they chose, with `counts:
   false` — their own death is sufficient on its own to make it not count,
   whatever their target's status — for as long as the underlying `:vote`
   `Action` row exists (owner decision 2026-09-13; this reverses this spec's
   earlier assumption that a since-dead voter's own vote disappears from what
   they see entirely). This is a corollary of rules 4, 9 and 10, but is kept
   as its own rule so a future change to any of them cannot silently drop the
   own-vote guarantee without a test noticing.
7. (withdrawn — no code in this bead can break it: it would only check that
   qss.5's `end_day` doesn't delete `:vote` rows. See Out of scope.)
8. The `:vote_tally` calculation is declared `public? true`, so a later
   GraphQL field (27w.3) can select it without any further domain-layer
   change — this is what "expose the tally as data the API can serve" means
   concretely for this bead, which stops at the domain code interface.
9. A **dead** game member (their own `Player.alive` is `false` in the
   phase's game — rule 10) reading `:vote_tally` gets rule 1's uniform map
   entirely unfiltered: every entry for every `:vote` row currently recorded
   in that phase, `counts: true` and `counts: false` alike — covering every
   currently-cast vote, not only the ones that currently count (owner
   decision 2026-09-13, "the dead see everything, as spectators in an
   afterlife"). This rule adds no separate computation of its own: the
   entries and their `counts` flags are exactly rule 1's/4's already-built
   ones (voter and target both alive — rule 4's filter-then-`tally/1`
   result), simply not narrowed down the way rule 4 narrows them for a living
   reader (to `counts: true` entries, plus that reader's own). A target
   named only by non-counting votes belonging to other players, which rule
   4's view would omit entirely for any living reader but the voter
   themselves, still appears as a key here (with only `counts: false`
   entries); a target with no `:vote` row naming it at all — counting or not
   — is absent from this map exactly as from rule 4's view.
10. Which subset of rule 1's uniformly-shaped entries a `:vote_tally` read
    returns — rule 4's (`counts: true`, plus the reader's own entry) or rule
    9's (every entry) — is decided once, by the reading actor's own seat in
    the phase's game, not by anything about the individual votes: the
    calculation reads the actor's own `Player` row for that phase's
    `game_id` (matched by `user_id`) and branches on its `alive` field:
    `true` yields rule 4's view, `false` yields rule 9's. When that lookup
    finds no `Player` row at all for the reading actor in that game —
    including when there is no actor at all — the result is `%{}` (rule 5)
    regardless of which view would otherwise apply: ordinarily this is
    because the underlying `:vote` read (rule 1) already returned no rows for
    a properly-authorized non-member, but even if rows had come back some
    other way (e.g. `authorize?: false`), this branch's own `Player` lookup
    still finds no seat to pick a real view for, so it must not fabricate
    one. A single `:vote_tally` read returns exactly one of rule 4's view,
    rule 9's view, or `%{}`; they never mix in one result.

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
- **A second, differently-defined notion of "currently alive" for votes**:
  not built. This bead's own calculation *does* filter `:vote` rows to a
  living voter and a living target before calling `tally/1` (rule 4) — that
  filtering is this bead's own code, not something `tally/1` or 27w.2's read
  policy does for it (`tally/1` is qss.5's unchanged, aliveness-agnostic
  grouping function; see rule 1). What this bead must not do is invent its
  own, separate definition of what makes a vote "count" — the filter it
  applies mirrors, exactly, the living-voter/living-target rule qss.5's own
  `ResolveLynch` reactor applies before its own call to the same `tally/1`
  (qss.5 rules 8-9), so a vote that counts toward the actual lynch always
  matches a `counts: true` entry here, and vice versa. Every entry's `counts`
  flag, for a living or a dead reader alike, is computed the same one way
  (rule 1) — there is exactly one live-vs-dead decision in this bead's code,
  reused for both views, never two that could drift apart.
- **Changing or withdrawing a day vote while alive** (qss.21): not built
  here. This bead reads whatever `:vote` row(s) exist for a phase at the
  moment `:vote_tally` is read — however a player's latest choice comes to
  be reflected there (an update in place, a replacement row, or a deletion on
  withdrawal) is qss.21's mechanism to build. `:vote_tally`'s live-read
  design (rule 1) already reflects whatever `:vote` rows exist at read time,
  with no cache to invalidate, so a later change or withdrawal shows up on
  the very next read with no change to this bead's code — but this bead does
  not implement, validate, or test the change/withdraw action itself, and
  `Depends on` does not name qss.21: nothing here requires it to exist first.
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
  added here. That bead will need to represent this one shape — a map from
  target id to a list of `%{voter_id:, counts:}` entries, the same for every
  reader — as whatever GraphQL type fits; which type, and how, is 27w.3's
  call, not this one's.
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
  a living actor holding a seat in that game, returns rule 1's uniform map
  filtered to `counts: true` entries only, matching `ResolveLynch.tally/1`'s
  own grouping of the same `:vote` rows exactly (rules 1, 2, 4); the identical
  phase called with an actor holding no seat in the game returns `%{}`
  (rules 1, 5) — this is the specific case that the original, load/3-based
  design would have failed, so the test must construct a genuine non-member
  actor and assert `%{}`, not merely assert against a member and stop; a
  phase with no `:vote` rows recorded at all (a night phase's `:kill` row, or
  a day phase before any vote is cast) returns `%{}` for a member too (rules
  2, 3, and qss.5 rule 4's empty case). A day phase whose `:vote` rows
  include one cast by a player who is now dead and one naming a target who
  is now dead — where the reading actor is neither of those two voters —
  called with a **living** actor, returns only the entries whose voter and
  target are both currently alive, `counts: true` (rule 4); the target named
  only by that dead voter's, or dead target's, vote is absent from the map
  as a key entirely, not present with an empty list (rule 4 — the specific
  case a calculation that empties a target's entry list without deleting the
  key would get wrong); the *identical* phase and votes, called with a
  **dead** actor instead, returns every one of those rows as an entry,
  including under that same target — the two non-counting ones marked
  `counts: false` and any others `counts: true` (rule 9) — proving the same
  underlying map (rule 1) is merely narrowed differently by rule 10, not
  recomputed from scratch for each audience. Separately, the same day phase
  called with the living actor who *is* the dead-target's voter: their own
  entry appears in their own result, marked `counts: false`, even though a
  plain `counts: true` filter alone would have excluded it — rule 4's
  own-vote exception (owner decision 2026-09-13, card decision 6) is what
  keeps it there for them specifically, and a different living actor reading
  the identical phase still does not see that entry at all. Every one of
  these calls must be made against seeded data shared within one test, not
  built fresh per assertion, so the same underlying map is visibly narrowed
  differently rather than recomputed — the specific bug this guards against
  is a calculation that returns rule 4's narrowed view regardless of the
  reader's own aliveness or identity. No test is needed for a `load/3`
  contract: this calculation declares no relationship dependency (rule 1) and
  relies on the default,
  no-op `load/3` that `use Ash.Resource.Calculation` already provides
  (`deps/ash/lib/ash/resource/calculation/calculation.ex:181`). When a test
  calls `calculate/3` directly and builds its own
  `Ash.Resource.Calculation.Context`, it must set `authorize?: true`, or
  leave it `nil`, which defaults to `true`, alongside the non-member actor. A
  context with `authorize?: false` would hand the member-only tally to
  everyone and hide exactly the leak rule 1 exists to prevent.
- `WerewolfAsh.Games.get_phase/1,2` (or `list_phases/0,1`) with
  `load: :vote_tally` — direct tests through the code interface, each
  supplying a distinct `actor`: a living game member who is not one of the
  phase's voters sees rule 4's view — only the entries that currently count;
  a dead game member reading the *same* phase sees rule 9's unfiltered view —
  every currently-cast vote in that phase, including one from a since-dead
  voter or naming a since-dead target, each carrying the correct `counts`
  flag (rules 4, 9, 10) — the test must seed both a counting and a
  non-counting vote in the same phase and assert the dead reader's result
  contains both, correctly marked, not merely that it is non-empty; the
  target named only by the non-counting vote must be absent from the living
  reader's map as a key entirely, not present with an empty entry list
  (rule 4). A vote cast by a player who has since died is absent from a
  *different*, still-living reader's view (rule 4) but present, marked
  `counts: false`, when that now-dead voter reads the same phase's tally
  *themselves* (rule 6) — the test must cast the vote, kill the voter, then
  read `:vote_tally` twice against the same phase: once as a different,
  still-living actor (entry absent) and once as the now-dead voter (entry
  present, `counts: false`). A vote naming a target who has since died, cast
  by a voter who is *still alive*, is absent from a *different* living
  reader's view (rule 4), present and marked `counts: false` for a dead
  reader (rule 9) — and present and marked `counts: false` for the voter
  *themselves*, still alive, reading the tally (rule 4's own-vote exception,
  owner decision 2026-09-13, card decision 6) — the test must read
  `:vote_tally` as three distinct actors against the one seeded vote (a
  different living member, a dead member, and the living voter themselves)
  and assert all three results differ exactly this way. An actor holding no
  seat in the game, and a call with no actor at all, both return `%{}`
  regardless of which view they would otherwise get (rule 5). A still-living
  voter whose chosen target is also still alive finds an entry with their own
  `voter_id` and `counts: true` under that target (rule 6). Reading
  `:vote_tally` on the game's current night phase (seeded with a `:kill` row)
  returns `%{}` for both a living and a dead reader, and the response never
  contains the kill's actor or target under any key for either (rules 2, 3).
- `Ash.Resource.Info.public_calculation(WerewolfAsh.Games.Phase, :vote_tally)`
  (`deps/ash/lib/ash/resource/info.ex:582-588`) — direct test: returns the
  calculation, not `nil` (rule 8).
- End to end, through the code interface: start a five-plus-player game, cast
  two or more `:vote` actions from different actors in the open day phase,
  then compare `Games.get_phase!(day.id, load: :vote_tally, actor: <a living
  game member>)`'s result, with each target's `counts: true` entries reduced
  to their bare `voter_id`s, against `ResolveLynch.tally/1` computed directly
  over the same phase's `:vote` actions fetched with `authorize?: false` —
  the two must be identical, proving rule 4's `counts: true` subset is
  exactly `tally/1`'s own grouping and not a separately-invented one (rule
  1). A second end-to-end pass against that same scenario: kill one of the
  voters (or one of the targets), then read `:vote_tally` as a dead game
  member and confirm the result contains every currently-cast vote with the
  correct `counts` flags, matching rule 9's definition (rules 9, 10).

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
  `Ash.Context.to_opts(context)` unchanged as that read's options, loading
  (or otherwise making available) each row's `actor.alive` and
  `target.alive` — needed for the `counts` flag below, since `Action` itself
  carries no aliveness, only its `actor`/`target` `Player` do; group the
  results by `phase_id`. For each phase, build the one uniform map rule 1
  describes: filter the phase's rows to those whose `actor.alive` and
  `target.alive` are both `true` — mirroring, not calling, qss.5's own
  identical filter in `ResolveLynch` (this bead does not call into qss.5's
  reactor or any of its private steps) — pass that subset to
  `WerewolfAsh.Games.Reactors.ResolveLynch.tally/1` to get the set of
  currently-counting `{target_id, voter_id}` pairs, then build the full map
  from *every* row in the phase's group (not just the filtered subset),
  grouped by target, each entry `%{voter_id:, counts:}` with `counts` set by
  whether that `{target_id, voter_id}` pair is in `tally/1`'s result. Only
  then does the reader's own aliveness (rule 10: look up whether the
  context's own actor has a living or dead `Player` seat in that phase's
  `game_id`) decide what's returned: the full map as-is for a dead seat
  (rule 9), or, for a living seat, that same map with each target's entry
  list filtered down to entries where `counts` is `true`, plus the reader's
  own entry (`voter_id` equal to the context's own actor's player id) even
  when its `counts` is `false` — dropping any target left with no entries at
  all under that combined rule (rule 4); no seat at all collapses to `%{}`
  either way (rule 5). Does not override
  `load/3` — the default no-op `use Ash.Resource.Calculation` already
  provides is correct here precisely because this calculation must not
  declare a relationship dependency (rule 1); loading `actor`/`target` is
  not that dependency and does not carry rule 1's `authorize?: false` risk —
  it is an ordinary `Ash.Query.load/2` (or equivalent) attached to the same
  explicit, top-level `Action` read rule 1 already requires inside
  `calculate/3`'s own body, which authorizes the loaded relationships the
  normal way, the same as any other query-level load; only a relationship
  declared through the *calculation's own* `load/3` callback takes the
  dangerous, always-`authorize?: false` path rule 1 warns about, and this
  calculation declares none. Its `@moduledoc` is where Assumption 1's
  open-ballot decision gets recorded, since the coder cannot write it to
  `CLAUDE.md`.
- No changes to `lib/werewolf_ash/games/action.ex`, `player.ex`, `game.ex`,
  `message.ex`, or any policy/authorizer/field-policy code — this bead reads
  `Player` (rule 10) but does not modify the `Player` resource itself; it
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
