# werewolf_ash-qss.21: Changeable day choices: change or withdraw a vote or protection while alive

Depends on: werewolf_ash-qss.18

## For the owner

**What changes.** While the day's vote is open, any living player can change
who they're voting for, or take their vote back entirely, right up until
voting closes. The bodyguard gets the same freedom over their chosen
protection, right up until night begins. Every other action a player takes
(the seer's look, the wolves' kill, the hunter's shot) still only counts
once. If the bodyguard who set up a protection dies before night falls, that
protection no longer saves anyone.

**Decisions.**
1. Can a living player change their day vote, or take it back, before voting
   closes? — **Decided:** yes, to any other living target in the game, right
   up until voting closes.
2. Can the bodyguard change or drop their chosen protection before night
   starts? — **Decided:** yes, right up until night starts.
3. Do any other actions (the seer's investigation, the wolves' kill, the
   hunter's shot) become changeable too? — **Decided:** no; only the day
   vote and the bodyguard's protection. Every other action stays one-shot: a
   second attempt is refused.
4. Does a changed vote or protection have to pass the same checks as a first
   one (actor still alive, target still alive and in the same game, no
   repeat-protecting the same player two days running)? — **Decided:** yes,
   identically.
5. If the bodyguard who set up a protection dies before night starts, does
   the protection still work? — **Decided:** no, it protects no one.
6. Can a dead player change or withdraw anything they did while alive? —
   **Decided:** no.
7. What happens if a player withdraws something they never made? —
   **Decided:** nothing; it quietly succeeds.

**Rule changes.** Already recorded in `CLAUDE.md`'s "Actions are used once"
rule ahead of this spec (owner decision 2026-09-13); quoted here for
reference, as this spec implements it: "Actions are used once: a player may
take each action type once per phase, and a second attempt is refused rather
than replacing the first. The two daytime choices are the exception (owner
decision 2026-09-13): while alive, a player may change or withdraw their day
vote until voting closes, and the bodyguard may change or withdraw their
protection until night starts. When the vote resolves, only living players'
current votes for living targets count, and a bodyguard who is dead when
night starts protects no one."

## Assumptions

Implementation choices below decision-card weight — none changes what a
player or the owner would notice, but each still shapes what a competent
implementer would build, so it is recorded here rather than left implicit.

1. **Recast mechanism.** Rules 1-2's "change" is the same `:create` action,
   made conditionally upsert-based for `:vote`/`:protect` only (see
   Acceptance's framework citation), not a separate dedicated action. This
   reuses every one of `:create`'s existing checks unchanged for a recast
   (rule 3) with no duplicated validation wiring, and matches CLAUDE.md's own
   wording that a second attempt now "replaces" rather than being refused.
2. **Uniform closed-phase check.** Rule 4's "phase already ended" rejection
   applies identically to a first `:vote`/`:protect` and to a recast, rather
   than being scoped to recasts alone. There is no reliable way, before the
   database is touched, to tell "this is a first attempt" from "this is a
   change" — both look like the same `:create` input — and no existing
   client path ever files a first vote or protection against an
   already-ended day phase, so treating them alike changes nothing a player
   would notice.
3. **Withdraw's shape.** `withdraw_action/3` takes `(phase_id, actor_id,
   type)` rather than an already-loaded `Action` struct, because a player
   withdrawing their own vote or protection knows their own identity and the
   phase, not the row's id.
4. **Withdraw's authorization timing.** Rule 11 makes `:withdraw`'s "actor's
   own seat only" policy conditional on whether `werewolf_ash-27w.2` has
   already merged, mirroring the same conditional handoff
   `werewolf_ash-qss.14` rule 14 already uses for `:update_settings`.

## Goal

A living player's day vote, and a living bodyguard's day protection, are no
longer locked in the instant they are first cast. Either may be redirected to
a new target, or withdrawn outright, any number of times while the actor is
alive and while the choice is still in play — a vote until voting closes, a
protection until night starts. Both remain governed by exactly the checks a
first vote or protection would face, evaluated fresh against whatever the
latest target is. Every other action a player can take — the seer's
investigation, the pack's kill, the hunter's shot — is untouched: filing a
second one in the same phase is still refused outright, exactly as today. And
because a protection is only as good as the bodyguard who set it up, a
protection recorded by a bodyguard who has since died no longer shields
anyone when the pack's kill resolves that night.

## Rules

1. While alive, a player may submit `Games.create_action(phase_id, actor_id,
   target_id, :vote)` again for a phase where they already hold a `:vote`
   action: instead of being refused, this updates that action's `target_id`
   to the new value, on the same row (the action keeps its `id`).
2. While alive, a bodyguard may submit `Games.create_action(phase_id,
   actor_id, target_id, :protect)` again for a phase where they already hold
   a `:protect` action: instead of being refused, this updates that action's
   `target_id` the same way as rule 1.
3. A recast `:vote` or `:protect` (rules 1-2) is checked exactly as a first
   one would be, evaluated against the new `target_id`: `TypeRequiresPhaseAndRole`
   (phase kind and, for `:protect`, the bodyguard role), `ActorAlive`, the
   existing self-protect check (`target_id != actor_id` for `:protect`), and
   — once `werewolf_ash-qss.18` lands — target-alive, same-game, and the
   no-repeat-protecting-the-same-player-two-days-running check. A recast that
   fails any of these is rejected the same way a first attempt would be, and
   leaves the existing row unchanged.
4. A `:vote` or `:protect` submitted through `create_action` — a first one or
   a recast — is rejected on field `:phase_id` when the phase it names has
   already ended (`ended_at` is not `nil`). Before `werewolf_ash-qss.15`
   lands, a day phase's `ended_at` is set at the exact moment night opens
   (`AdvancePhase.close_phase/3`, `lib/werewolf_ash/games/game/changes/advance_phase.ex:66-68`),
   so this one check is both "voting has closed" for a vote and "night has
   started" for a protection.
5. `:investigate` and `:shoot` are unaffected by rules 1-4: a second
   `create_action`/`create_kill_action` for the same actor, phase and type is
   refused exactly as before this bead, reporting the same `field: :phase_id`
   error the `one_per_actor_per_phase_per_type` identity already produces.
6. `WerewolfAsh.Games` gains `withdraw_action/3`, taking `(phase_id,
   actor_id, type)`, backed by a generic Ash action (`type: :action`) rather
   than a `:destroy` action on an already-loaded record — the caller supplies
   identifying values, not a row, so `:withdraw`'s `phase_id`/`actor_id`/
   `type` are `Ash.ActionInput` arguments, not changeset attributes (this is
   a real constraint on rules 7, 8 and 11 below, not just an implementation
   preference: see each). Given `type: :vote` or `type: :protect`, it deletes
   the actor's existing action of that type in that phase. Any other `type`
   is rejected on field `:type`.
7. `withdraw_action/3` is rejected on field `:actor_id` when the actor is not
   currently alive. `WerewolfAsh.Games.Action.Validations.ActorAlive` is
   reused for this, extended with a second `validate/3` clause that reads the
   `:actor_id` value off an `Ash.ActionInput` (`Ash.ActionInput.get_argument/2`,
   `deps/ash/lib/ash/action_input.ex:516`) instead of
   `Changeset.get_attribute/2` when it is invoked on `:withdraw` — its
   existing `:create`/`:kill` clause, and their existing tests, are
   unchanged. This is possible because Ash validations are defined against
   `Ash.Changeset.t() | Ash.ActionInput.t()` interchangeably
   (`deps/ash/lib/ash/resource/validation.ex:69-72`) and generic actions run
   their declared validations the same way changesets do
   (`deps/ash/lib/ash/action_input.ex:1350-1436`). Reusing `ActorAlive` on
   `:withdraw` at all also requires overriding its `supports/1` callback:
   `use Ash.Resource.Validation` defaults `supports(_opts)` to
   `[Ash.Changeset]` (`deps/ash/lib/ash/resource/validation.ex:189`), and a
   generic action's own validation runner checks the running validation's
   `supports/1` against `Ash.ActionInput` before calling `validate/3` at all,
   raising `Ash.Error.Framework.UnsupportedSubject` if it is not listed
   (`deps/ash/lib/ash/action_input.ex:1345-1347`) — so `ActorAlive` must
   override `supports/1` to return `[Ash.Changeset, Ash.ActionInput]`, or the
   new `Ash.ActionInput` clause required above is never reached at all.
8. `withdraw_action/3` is rejected on field `:phase_id` when the named phase
   has already ended, by the same rule 4 uses. The new "phase not ended"
   validation needs the identical `Ash.ActionInput` clause *and* the
   identical `supports/1` override described in rule 7 to be reusable,
   unchanged, on both `:create` (a `Changeset`) and `:withdraw` (an
   `Ash.ActionInput`) — this module is written from scratch by this bead, so
   there is no pre-existing default `supports/1` to forget to override, but
   the override is just as required here as it is for `ActorAlive`.
9. `withdraw_action/3` quietly succeeds and changes nothing when the actor
   holds no `:vote`/`:protect` action of the given type in the given phase:
   no row is created, removed, or otherwise touched, and no error is raised.
10. `WerewolfAsh.Games.Action.Changes.ApplyKill`'s protection lookup
    (`protected?/2`, `lib/werewolf_ash/games/action/changes/apply_kill.ex:43-59`)
    ignores a `:protect` action whose actor is not alive at the moment the
    kill resolves: a target counts as protected only when at least one
    matching `:protect` row's actor is currently alive. A target protected
    earlier that day by a bodyguard who has since died is treated as
    unprotected, and the kill lands on them exactly as if no one had
    protected them.
11. If `WerewolfAsh.Games.Action` already declares `authorizers:
    [Ash.Policy.Authorizer]` at implementation time (i.e. `werewolf_ash-27w.2`
    has merged), the new `:withdraw` action gains a policy forbidding it
    unless the `Player` named by the `:actor_id` argument has `user_id` equal
    to the calling actor's id — the same "actor's own seat only" outcome
    27w.2 gives `:create`/`:kill`, but checked differently because rule 6
    makes `:withdraw` a generic action with no row: there is no `actor`
    relationship on a changeset-to-be for a `relates_to_actor_via`/
    `expr(exists(actor, ...))`-style check to traverse (that mechanism is
    what `:create`/`:kill` can use, since `actor_id` is an attribute on a
    real, queryable relationship there). Instead the check reads the
    `:actor_id` *argument*'s value directly and looks up the `Player` it
    names, the same way rule 7 does. This is a genuine, supported Ash
    mechanism, not a workaround: `Ash.Policy.SimpleCheck.match?/3` (used for
    checks that are not row filters, e.g. the existing
    `AshAuthentication.Checks.AshAuthenticationInteraction` bypass this
    codebase already relies on) receives the full `Ash.Policy.Authorizer.t()`
    as its context, which carries the in-flight `action_input:
    Ash.ActionInput.t() | nil` field directly
    (`deps/ash/lib/ash/policy/authorizer/authorizer.ex:32`); a check can call
    `Ash.ActionInput.get_argument(action_input, :actor_id)`
    (`deps/ash/lib/ash/action_input.ex:516`) to read it, matching how Ash's
    own built-in `Ash.Policy.FilterCheck` machinery resolves an `arg(...)`
    template against `action_input.arguments` for exactly this subject type
    (`deps/ash/lib/ash/policy/filter_check.ex:154-164`). Anyone else's
    `actor_id`, or no actor at all, is forbidden. If `Action` has no policy
    authorizer yet, `:withdraw` is left exactly as open as every other
    unnamed action (`authorize_if always()`), and 27w.2 must add the matching
    check when it lands — the same conditional handoff
    `werewolf_ash-qss.14` rule 14 already uses for `:update_settings`. The
    recast path (rules 1-2) needs no policy change of its own: it runs
    through the existing `:create` action, whose `actor_id` *is* a changeset
    attribute on a real relationship, and which 27w.2's own spec already
    names.
12. Rules 7 and 8 are checked before rule 9's "nothing to withdraw" case: a
    dead actor (rule 7) or an already-ended phase (rule 8) is rejected even
    when the actor also holds no matching action to withdraw. "Nothing to
    withdraw" only quietly succeeds once the actor-alive and phase-not-ended
    checks have both passed — it never overrides them.
13. `ApplyKill`'s new actor-alive read (rule 10) uses the same `opts` as every
    other call in `protected?/2`, whatever those are at implementation time —
    it does **not** introduce `authorize?: false`, and it does not remove it
    either. Today `protected?/2` passes **no** `authorize?: false`: `change/3`
    builds `opts` from `Context.to_opts(context)`
    (`lib/werewolf_ash/games/action/changes/apply_kill.ex:28`) and threads
    that same `opts` — carrying whichever actor and `authorize?` setting the
    triggering `:kill` action itself ran with — through every call in
    `protected?/2` (lines 43-59); `werewolf_ash-27w.2`'s own spec lists no
    change to this file. If a later bead (27w.2 or otherwise) adds
    `authorize?: false` to these calls before or after this one, rule 10's
    new call follows suit by using the same `opts` variable, with no special
    case of its own; this bead neither adds nor removes that flag here.

## Out of scope

- Counting votes at resolution — dropping a since-dead voter's vote or a vote
  for a since-dead target — is `werewolf_ash-qss.5`'s job. This bead only
  makes the underlying `:vote` rows changeable and withdrawable; it does not
  touch how or when they are tallied.
- Who can see the live tally, and when a change or withdrawal shows up in it
  — `werewolf_ash-qss.16`. This bead changes what `:vote`/`:protect` rows
  exist and when; qss.16 decides who is shown which of them.
- `werewolf_ash-qss.15`'s separate, earlier vote deadline. This bead's
  "voting has closed" check (rule 4) is keyed to the day phase's own
  `ended_at`, which is today's only deadline. When qss.15 adds its own
  earlier vote-deadline attribute, checking it is qss.15's own change to make
  wherever it lands; this bead does not add that attribute or wire a second
  deadline.
- Any GraphQL mutation, or a friendlier public name for "change a vote" (e.g.
  a dedicated `changeVote` mutation) — `werewolf_ash-27w.3`'s territory. This
  bead only changes/adds behaviour on the domain code interface.
- Making `:investigate` or `:shoot` changeable or withdrawable — explicitly
  ruled out (Decision 3, and CLAUDE.md's own rule).
- Any database migration. No attribute, relationship or identity is added;
  the existing `one_per_actor_per_phase_per_type` identity's unique index
  (already a full, unconditional index — see `identity_wheres_to_sql` in
  `lib/werewolf_ash/games/action.ex:23`, which only carves out a partial
  index for `one_kill_per_phase`) is reused as the recast's conflict target
  as-is.
- Any policy on `Action` beyond `:withdraw`'s conditional one (rule 11) —
  everything else `werewolf_ash-27w.2` plans for `Action` is that bead's own
  work, unaffected by this one.
- `werewolf_ash-qss.20`'s own edits to `action_test.exs`/`started_game/0` —
  a different bead touching the same file, at different lines and for a
  different reason (already flagged as a parallel, unrelated diff by
  `werewolf_ash-qss.18`'s own spec). Do not fold qss.20's changes into this
  bead's diff.
- Adding a second, non-vote duplicate-refusal example to
  `test/werewolf_ash/games_test.exs`'s "allows one action per actor, phase
  and type" test. That coverage (rule 5) is added once, in
  `test/werewolf_ash/games/action_test.exs`, which already has the full role
  fixtures (`started_game/0`) needed to exercise `:investigate`/`:shoot`
  cheaply; `games_test.exs`'s bare fixture does not, and duplicating the case
  in both files buys nothing.

## Acceptance

- `WerewolfAsh.Games.create_action/4,5` — direct tests: a second `:vote` call
  for the same actor and phase with a different target succeeds and updates
  the same row's `target_id` (rule 1); the same for `:protect` (rule 2); a
  recast targeting a dead player (or, once `werewolf_ash-qss.18` lands, a
  cross-game player) is rejected the same way a first one would be (rule 3);
  a recast by a now-dead actor is rejected on `:actor_id` (rule 3); a
  `:vote`/`:protect` call — first or recast — against an already-ended day
  phase is rejected on `:phase_id` (rule 4); a second `:investigate` (or
  `:shoot`) attempt in the same phase still refuses with the pre-existing
  `field: :phase_id` error (rule 5).
- New validation module (name advisory, e.g.
  `WerewolfAsh.Games.Action.Validations.PhaseNotEnded`) — direct unit tests
  on its `validate/3`: `:ok` when the named phase's `ended_at` is `nil`; an
  error on field `:phase_id` when it is set (rule 4); both cases repeated
  against an `Ash.ActionInput` built for `:withdraw`, not just a `Changeset`
  built for `:create` (rule 8).
- `WerewolfAsh.Games.Action.Validations.ActorAlive.validate/3` — in addition
  to its two existing `Changeset`-based tests (unchanged), new direct tests
  for the `Ash.ActionInput` clause added by rule 7: `:ok` for a living
  actor's id supplied as the `:actor_id` argument; an error on field
  `:actor_id` for a dead one — built the same way the existing tests build a
  bare `Changeset` (`Ash.ActionInput.for_action/3` or `new/1` +
  `set_argument/3`, mirroring `Changeset.new/1` + `change_attribute/3`).
- The `:withdraw` action's `Ash.Resource.Actions.Implementation` module (or
  equivalent, name advisory) — direct unit test(s) on its own lookup logic:
  given a matching row, it is destroyed; given none, nothing changes and no
  error is raised (rule 9); given a dead actor or an already-ended phase, the
  rejection happens even when no matching row exists either — proving rule
  12's ordering (checks first, "nothing to withdraw" only once they pass).
- New change module (name advisory, e.g.
  `WerewolfAsh.Games.Action.Changes.UpsertChangeableTypes`) — direct unit
  test(s) on its `change/3`: for `type: :vote`/`:protect` it marks the
  changeset to upsert on the `one_per_actor_per_phase_per_type` identity with
  `upsert_fields: [:target_id]`; for `type: :investigate`/`:shoot` it leaves
  the changeset unmarked (rules 1, 2, 5). Framework citation for the
  mechanism this module relies on: `Ash.Changeset.for_create/4` runs an
  action's declared `change`s while building the changeset, before
  `Ash.create/2` ever reaches the data layer
  (`deps/ash/lib/ash/changeset/changeset.ex:2017-2026`, already cited by
  `werewolf_ash-qss.18`'s own spec for the same reason); the data layer call
  itself then derives whether to upsert, and with which identity and fields,
  by reading `changeset.context[:private][:upsert?]` /`:upsert_identity` /
  `:upsert_fields` off that already-built changeset, falling back to the
  action's own static `upsert?`/`upsert_identity`/`upsert_fields` only when
  the context does not set them (`deps/ash/lib/ash/actions/create/create.ex:137-156`,
  `do_run/4`) — so a `change` that conditionally calls
  `Ash.Changeset.set_context(changeset, %{private: %{upsert?: true,
  upsert_identity: :one_per_actor_per_phase_per_type, upsert_fields:
  [:target_id]}})` only for `:vote`/`:protect` is sufficient; no static
  `upsert?`/`upsert_identity`/`upsert_fields` needs to be declared on the
  `:create` action's own DSL, and `:investigate`/`:shoot` calls through the
  same action are untouched.
- `WerewolfAsh.Games.withdraw_action/3` — direct tests per rules 6-9: a
  living actor withdrawing an existing `:vote` deletes it; the same for
  `:protect`; any other `type` is rejected on `:type`; a dead actor's
  withdrawal is rejected on `:actor_id`; withdrawal against an already-ended
  phase is rejected on `:phase_id`; withdrawal with no matching action
  quietly succeeds and leaves the actor's actions for that phase unchanged
  (rule 9), asserted by checking the row count before and after, not by
  expecting any particular return value. If `Action` already carries
  `authorizers: [Ash.Policy.Authorizer]` at implementation time, an
  additional test calling `withdraw_action/3` with an `:actor_id` naming a
  `Player` seated by a *different* user than the calling actor is forbidden
  with a policy-class error (rule 11); if it does not yet carry the
  authorizer, no such test applies yet, and 27w.2 adds it when it lands.
- `WerewolfAsh.Games.Action.Changes.ApplyKill.change/3` — new test case
  (alongside the three already in `apply_kill_test.exs`): a target protected
  that day by a bodyguard who is dead by the time the kill resolves dies
  exactly as if never protected (`result: %{"killed" => true}`, and
  `Games.get_player!(target.id).alive == false`) (rule 10).
- End to end, through the domain code interface: a villager casts a day
  vote, recasts it for a different target, then withdraws it entirely —
  `Games.list_actions!(query: [filter: [phase_id: ..., actor_id: ...,
  type: :vote]])` for that phase and actor comes back empty. Separately: a
  bodyguard protects player X, recasts to protect player Y instead, and the
  werewolf's night kill on X (not Y) then succeeds, proving the recast
  actually moved the protection rather than adding to it. A third scenario:
  a bodyguard protects a target, the bodyguard dies before night starts
  (some other way), and the werewolf's night kill on the originally
  protected target succeeds — exercising rule 10 through the full
  `create_action`/`end_day`/`create_kill_action` path, not just at the
  `ApplyKill` unit level.

### Existing tests this will break

Grep for every call site of the two actions this bead changes:

```
grep -rn "create_action\|create_kill_action" test/ --include="*.exs"
```

Full output (call sites only; `describe`/module lines omitted) is reproduced
in Touches-adjacent detail below where it matters. Two different rules break
two different kinds of existing call: rule 1/2's "a second same-type call now
replaces, instead of being refused" breaks a call that relied on the old
refusal; rule 4's "a `:vote`/`:protect` against an already-ended phase is
rejected" breaks a call that reuses a `day` phase variable captured *before*
`end_day!` but only invoked *after* it, once that same row's `ended_at` is
already set.

**Rule 1/2 (recast replaces, not refuses) — two sites:**

- **`test/werewolf_ash/games/action_test.exs:169-182`, the test "refuses a
  second action of the same type in the same phase (rule 9)", is stale and
  must change.** It casts a `:vote` at line 174
  (`Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote)`), then
  asserts at lines 176-177 that a second `:vote` call for the same actor and
  phase with a different target
  (`Games.create_action(day.id, p.villager.id, p.bodyguard.id, :vote)`) is
  refused with `{:error, %Ash.Error.Invalid{errors: [%{field: :phase_id}]}}`,
  and that the original row is `unchanged` (lines 179-181). Under rule 1,
  that second call now succeeds and replaces the target on the same row: the
  test's own premise (a second `:vote` in the same phase is always refused)
  is what changed, not a bug. The rule is correct as stated in this spec; the
  test is testing qss.4-era behaviour that this bead deliberately overrides
  for `:vote`. Fix: repurpose this test into this bead's own rule-1
  acceptance case — assert the second call succeeds, that
  `Games.get_action!(first.id).target_id` now equals the second call's
  target, and that exactly one `:vote` row still exists for that actor and
  phase (`Games.list_actions!(query: [filter: [phase_id: day.id, actor_id:
  p.villager.id, type: :vote]]) |> length() == 1`) — proving a replace, not
  an insert. Coverage that a second attempt at a type this bead does not
  touch is still refused (the actual, narrower survival of qss.4's rule 9)
  needs its own new test using `:investigate` or `:shoot` — `started_game/0`
  already deals every role, so e.g. two `:investigate` calls from `p.seer`
  in the same night phase, or two `:shoot` calls from `p.hunter` once
  `force_state(game, :hunter_pending)` is set, reproduce the exact assertion
  this test used to make, for a type rule 5 leaves untouched.

- **`test/werewolf_ash/games_test.exs:663-677`, the test "allows one action
  per actor, phase and type", has one stale assertion.** It casts a `:vote`
  at line 664 (`Games.create_action!(ctx.phase.id, ctx.alice.id, ctx.bob.id,
  :vote)`), then asserts at lines 666-667 that a second `:vote` call for the
  same actor and phase with a different target
  (`Games.create_action(ctx.phase.id, ctx.alice.id, ctx.alice.id, :vote)`)
  is refused the same way, for the same reason as above. This one assertion
  is stale; the rest of the test is not: the "a different type in the same
  phase is fine" case (lines 670-673, casting `:protect` alongside the
  existing `:vote`) and the "same type in another phase" case (lines 676-677,
  casting `:vote` again in a freshly created `day2`) both remain true
  regardless of this bead — neither one attempts a second action of the same
  type in the *same* phase, which is the only thing rule 1 changes. Fix:
  change the assertion at lines 666-667 to expect success and to confirm the
  existing row was updated in place (mirroring the `action_test.exs` fix
  above) rather than erroring. Per Out of scope, this file does not also
  gain a non-vote duplicate-refusal case — that lives in `action_test.exs`.

**Rule 4 (phase already ended) — three sites, found by tracing every `day`/
`night` variable in `action_test.exs` forward from its `current_phase` call
to every later use, specifically looking for a `:vote`/`:protect` call issued
*after* an `end_day!` call that closes the same variable's underlying row:**

- **`test/werewolf_ash/games/action_test.exs:243-254`, the test "a protected
  target survives; the kill is spent" (inside `describe
  "create_kill_action/3,4"`), is stale and must change.** That describe
  block's shared `setup` (lines 208-214) calls `Games.end_day!(game, %{now:
  @dusk})` before every test body runs, so by the time this test's own body
  executes, the `day` phase it is handed already has `ended_at` set. The test
  then calls `Games.create_action!(day.id, p.bodyguard.id, p.villager.id,
  :protect)` at line 248 — a first-ever `:protect` filed against an
  already-ended day phase. Under rule 4 this is now rejected on `:phase_id`,
  so the suite goes red. **Rule 4 must not be loosened to fix this** — it is
  correct as stated, and Assumption 2 already gives the reason it applies to
  a first attempt as well as a recast; the test's setup is what is stale.
  Fix: this test cannot use the describe block's shared, already-closed
  `day`; restructure it to file the bodyguard's protection while day is
  still open and only then close the day — the "protected-kill path"
  end-to-end test at lines 331-344 already does exactly this (calls
  `started_game/0` directly, protects during the still-open day, and only
  then calls `end_day!`) and is the pattern to follow, either by giving this
  test its own inline setup instead of the block's, or by folding its
  assertion into the "end to end" describe block alongside that sibling.
  Nobody is marked dead anywhere in this test, so it carries no win-at-dusk
  risk (see below) regardless of restructuring.

- **`test/werewolf_ash/games/action_test.exs:91-114`, the test "rejects a
  dead actor's vote, investigation or protection (rule 1)", has two stale
  assertions, and its most direct fix opens a second, independent trap.**
  `day = current_phase(game)` is captured at line 95, then
  `Games.end_day!(game, %{now: @dusk})` closes that same row at line 96 —
  *before* the three rejection assertions run. The `:vote` assertion at
  lines 103-104 and the `:protect` assertion at lines 109-110 both call
  `Games.create_action(day.id, ...)` against that now-closed phase, with an
  already-dead actor. Today both produce a single `field: :actor_id` error
  (from `ActorAlive`); once rule 4 exists, both *also* fail the new
  phase-not-ended check, and Ash runs every declared validation rather than
  stopping at the first failure unless one sets `only_when_valid?: true`
  (default `false` — the same behaviour `werewolf_ash-qss.14`'s own spec
  cites for the identical reason), so each becomes a two-element error list
  and the exact one-element pattern `[%{field: :actor_id}]}` no longer
  matches either assertion. (The `:investigate` assertion at lines 106-107,
  against `night.id`, is unaffected — rule 4 never applies to `:investigate`,
  per rule 5.) Per `werewolf_ash-qss.18`'s own spec, line 110's target is
  already changed from `p.villager.id` to `p.werewolf.id` by the time this
  bead is implemented (qss.18's own fixture fix, for an unrelated
  double-error collision with its `TargetAlive` validation) — that change is
  independent of this one and does not affect it either way.

  **The obvious fix — reorder so both day-phase assertions run before
  `Games.end_day!`, with all three players (villager, seer, bodyguard)
  already marked dead (currently lines 99-101) — is itself broken, and must
  not be used as written.** Marking all three dead first leaves only the
  werewolf and the hunter alive: 1 wolf against 1 non-wolf, and
  `CheckWin.decide/1` calls an equal or greater wolf count a wolves win
  (`lib/werewolf_ash/games/reactors/check_win.ex:83-84`). `werewolf_ash-qss.5`
  is open with no dependency relationship to this bead in either direction;
  if it merges first, `end_day!` composes that win-check, so a wolves win
  right at dusk finishes the game and opens no night phase, and
  `current_phase(night_game)` (line 97) returns `nil` — `night.id` then
  raises. This has to hold regardless of merge order, since nothing pins
  qss.21 to land before or after qss.5.

  Fix: mark only the villager and the bodyguard dead before `end_day!`, run
  both day-phase assertions (`:vote`, `:protect`) while `day` is still open,
  then call `Games.end_day!`, mark the seer dead, and only then run the
  `:investigate` assertion against the resulting `night`. Marking just the
  villager and bodyguard dead leaves the werewolf, the seer and the hunter
  alive at the moment `end_day!` runs — 1 wolf against 2 non-wolves — so
  `CheckWin.decide/1` returns `:continue` and a night phase opens normally
  whether or not `werewolf_ash-qss.5` has merged; the seer is marked dead
  afterward, which is fine, since only its own `:investigate` attempt
  (against the already-open `night`) needs it dead by then. None of this
  changes what rule 1 (`ActorAlive`) is proving — all three players are dead
  by the time each of them is tested, only the order relative to `end_day!`
  and to each other moves; the closing `Games.list_actions!(...) == []`
  checks for both `day.id` and `night.id` (lines 112-113) still hold either
  way.

- **`test/werewolf_ash/games/action_test.exs:140-152`, the test "rejects
  :protect outside a day phase, or by a non-bodyguard (rule 5)", has one
  stale assertion.** `day = current_phase(game)` is captured at line 144,
  then closed by `Games.end_day!(game, %{now: @dusk})` at line 145. The
  second assertion, at lines 150-151
  (`Games.create_action(day.id, p.villager.id, p.werewolf.id, :protect)`),
  calls a non-bodyguard actor against that now-closed day phase: today it
  fails on `field: :type` alone (`TypeRequiresPhaseAndRole`'s role check);
  once rule 4 exists it also fails the phase-not-ended check, for the same
  two-errors-not-one reason as above. The first assertion (lines 147-148,
  `night.id`, a bodyguard attempting `:protect` on the fresh night phase) is
  unaffected — `night.ended_at` is `nil`. Fix: reorder the two assertions so
  the day-phase one (currently second) runs *before* `Games.end_day!`, and
  the night-phase one (currently first) runs after it — the test's title and
  the two conditions it demonstrates (wrong phase kind; wrong role) are
  unchanged, only which one runs first. Nobody is marked dead in this test,
  so it carries no win-at-dusk risk.

Re-grepped the rest of the suite for the same pattern (a `:vote`/`:protect`
call whose phase variable was captured before, but only called after, an
`end_day!`/`end_night!` in the same test) and, separately, for any other
reordered setup that marks a player dead before an `end_day!` it relies on —
found no further instances of either:

- Every remaining `create_action`/`create_kill_action` call site in both
  files either targets a phase that is never closed during that test, is a
  freshly opened phase (`night`/`day2`, always created *after* the relevant
  `end_day!`/`end_night!` and used immediately), or is a type
  (`:investigate`, `:shoot`, `:kill`) rule 4 does not govern — confirmed by
  reading every remaining line the grep above returns: `action_test.exs`
  lines 52, 68, 76, 86, 107, 121, 134, 137, 148 (as fixed above), 158, 166,
  187, 190, 196, 203; the rest of `describe "create_kill_action/3,4"` (lines
  216-241, 256-293) never calls `create_action` with `:vote`/`:protect` at
  all; the "end to end" describe block's other two tests ("day/night path",
  lines 297-329, protects/votes at 301-302 before its own `end_day!` at 304;
  "hunter path", lines 346-358, makes no `:vote`/`:protect` call at all)
  are both unaffected either way; `games_test.exs`'s `describe "actions"`
  block (lines 644, 664, 667, 673, 677, 682, 686) never calls
  `end_day!`/`AdvancePhase` at all, so no phase there is ever closed;
  `action/changes/apply_kill_test.exs:49` uses a raw `generate(phase(...))`
  fixture with no `AdvancePhase` call anywhere in that file, so `ended_at`
  is never set there either.
- None of these remaining sites, nor the three fixes above apart from the
  "rejects a dead actor's..." one, mark any player dead before an `end_day!`
  call they depend on, so none of them can trip the same win-at-dusk trap:
  the `create_kill_action` describe block's tests either mark no one dead
  before the block's shared `end_day!` (its `setup`, lines 208-214, runs
  before any player is touched) or mark the werewolf dead only *after* the
  block's `end_day!` has already run (line 235, in "rejects a dead actor, a
  non-werewolf actor..."), which is too late to affect that `end_day!`'s own
  win-check either way; "day/night path" and "protected-kill path" mark no
  one dead before their own `end_day!` calls at all.

```
grep -rn "withdraw_action\|:withdraw\b" test/ lib/ --include="*.exs" --include="*.ex"
```
No hits anywhere in the repository — `withdraw_action/3` and the `:withdraw`
action are both new, so nothing existing calls or breaks on them.

## Touches

Advisory only; the coder may deviate.

- `lib/werewolf_ash/games/action.ex` — wire the new change (rules 1, 2, 5)
  and the new "phase not ended" validation (rule 4) onto `:create`, scoped
  to `type in [:vote, :protect]`, alongside the existing `ActorAlive`/
  `TypeRequiresPhaseAndRole` wiring; add the new `:withdraw` action (rules
  6-9), a generic action (`type: :action`, per rule 6) backed by an
  `Ash.Resource.Actions.Implementation` module that resolves
  `(phase_id, actor_id, type)` to the matching row and either destroys it or
  succeeds as a no-op, with the same `ActorAlive`/"phase not ended"
  validations reused from `:create`; rule 11's conditional policy on
  `:withdraw`, a custom `Ash.Policy.SimpleCheck` module (only added if
  `Action` already carries `authorizers: [Ash.Policy.Authorizer]`) reading
  the `:actor_id` argument off `context.action_input`. Also update the
  moduledoc (currently lines 7-10: "submitting the same type again in the
  same phase is refused outright — no upsert, no replacing the earlier
  choice") — that statement becomes false for `:vote`/`:protect` under this
  bead and must be corrected to describe the new recast/withdraw behaviour.
- `lib/werewolf_ash/games/action/changes/` (new module) — rules 1, 2, 5.
- `lib/werewolf_ash/games/action/validations/` (new module) — rules 4, 8;
  needs the same `Ash.ActionInput` handling, including the `supports/1`
  override, described next.
- `lib/werewolf_ash/games/action/validations/actor_alive.ex` — add the
  second `validate/3` clause for `Ash.ActionInput` described in rule 7,
  alongside the existing `Changeset`-based clause (line 21), which stays
  unchanged along with its existing tests; also override `supports/1` to
  return `[Ash.Changeset, Ash.ActionInput]` instead of `use
  Ash.Resource.Validation`'s default `[Ash.Changeset]` only (rule 7).
- `lib/werewolf_ash/games/action/changes/apply_kill.ex` — `protected?/2`
  (lines 43-59) gains the actor-alive check described in rule 10, using the
  same `opts` every other call in the function already uses — today that is
  the triggering `:kill` action's own `opts` (no `authorize?: false`), per
  rule 13.
- `lib/werewolf_ash/games.ex` — add `define :withdraw_action, action:
  :withdraw, args: [:phase_id, :actor_id, :type]`, alongside the existing
  `Action` defines.
- `test/werewolf_ash/games/action_test.exs` — the rule-1 fix at lines
  169-182; the three phase-already-ended fixes at lines 91-114 (mind the
  win-at-dusk trap — see "Existing tests this will break"), 140-152 and
  243-254 (reorder each so its day-phase assertion runs before the test's
  `end_day!` call); the new non-vote duplicate-refusal test (rule 5); new
  withdraw tests (rules 6-9, 12); the new phase-ended rejection tests for
  `create_action` (rule 4).
- `test/werewolf_ash/games_test.exs` — the one-assertion fix at lines
  666-667.
- `test/werewolf_ash/games/action/changes/apply_kill_test.exs` — the new
  dead-bodyguard test case (rule 10).
- `test/werewolf_ash/games/action/validations/actor_alive_test.exs` — new
  test case(s) for the `Ash.ActionInput` clause (rule 7), alongside the
  existing `Changeset`-based tests, which are unaffected.
- `test/werewolf_ash/games/action/validations/` (new test file) — the new
  "phase not ended" validation module's own direct unit tests, covering both
  the `Changeset` shape (used by `:create`) and the `Ash.ActionInput` shape
  (used by `:withdraw`); this module also needs the `supports/1` override
  described in rule 8, or `:withdraw` raises `Ash.Error.Framework.UnsupportedSubject`
  the moment it runs.
- `test/werewolf_ash/games/action/changes/` (new test file) — the new change
  module's own direct unit tests.
- A test file for the `:withdraw` action's `Ash.Resource.Actions.Implementation`
  module (location follows whatever name the coder gives it) — its own
  direct unit test(s) on the lookup-then-destroy-or-no-op contract (rules
  6, 9, 12), per the test standard's rule that every reactor/implementation
  module gets direct coverage on its own contract, not only through its
  caller.
- No `priv/repo/migrations/` or `priv/resource_snapshots/` changes are
  expected — see Out of scope.
