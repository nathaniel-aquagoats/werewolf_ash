# werewolf_ash-qss.14: Owner-configurable game setup: role distribution, optional specials, player bounds

Implemented in PR #19.

Depends on: none

## For the owner

**What changes.** Game owners will be able to choose how roles are dealt out (automatic by player count, or a manual werewolf count), turn the seer, bodyguard, and hunter roles on or off, and set a minimum and maximum number of players — instead of these being fixed at one seer, one bodyguard, one hunter, an automatic wolf count, and a minimum of 5 with no maximum. These can be changed any time before the game starts, then lock for that game. A game nobody configures behaves exactly as it does today. The maximum is a hard limit: once a game is full, nobody else can join, even if two people try at the exact same instant. The owner also can't set the maximum below however many people are already seated — that change is refused outright, and nobody is removed.

**Decisions.**
1. **Decided (2026-09-13):** the maximum player count is strict. Two people joining a capped game at the exact same instant can never both squeeze in past `max_players` — one of the two is always refused, never both accepted. This reverses the earlier recommendation on this card, which had accepted the race; Rule 15 gives the mechanism and explains why no automated test can tell it apart from an unlocked, racy version of the same check.
2. **Decided:** new games keep today's defaults — one seer, one bodyguard, one hunter, automatic wolf count, minimum 5, no maximum. No existing game changes behaviour.
3. **Decided:** `min_players` and `max_players` must each be at least 1 when set.
4. **Decided:** settings lock once the game starts; changing them once the game has left `:lobby` is refused.
5. **Decided:** this bead works correctly regardless of build order relative to the separate "who can change what" permissions work (`27w.2`) — only the owner can ever change their game's settings, whichever lands first.
6. **Decided (2026-09-13):** everyone counts toward the cap. The owner's own
   seat and any players seated when the game is created occupy capacity
   exactly like a player who joins later — a `max_players` of 8 means 8
   players in total, however they got their seat. This reverses the earlier
   recommendation on this card. Rule 15 explains exactly where this bites in
   practice: `add_player` (Rule 16), not `Game.create` itself — `max_players`
   can't be set until after a game already exists, so `Game.create`'s own
   seeding can never violate a cap no matter who counts toward it.
7. **Decided:** can the owner set the maximum below the number of players
   already seated? No, it's refused — `:update_settings` rejects the whole
   call, nobody is removed, and the game's settings are left exactly as
   they were. Setting it equal to the seated count is allowed.

**Rule changes.** None. This bead adds new owner controls; it does not change any settled rule in CLAUDE.md.

## Assumptions

The bead leaves several things unstated. These are the calls made to remove
that vagueness; the user should read this section first and can overrule any
of it.

1. **New action name.** This bead adds an update action on `Game` named
   `:update_settings` (domain interface `Games.update_game_settings/1,2,3`,
   mirroring the `define :update_game, action: :update` pattern already in
   `lib/werewolf_ash/games.ex`). It reuses
   `WerewolfAsh.Games.Game.Validations.ActorIsOwner` unmodified for the
   owner-only rule (Rule 2) regardless of merge order with
   `werewolf_ash-27w.2` (policies) — see Rule 14 for the conditional policy
   this bead adds on top of it when 27w.2 has already merged. If 27w.2 merges
   after this bead instead, its own NOTES (2026-09-12) already commit it to
   naming whichever new action landed first, so no coordinator hand-off is
   needed either way.
2. **Edit-time composition check applies to both modes, evaluated at
   `max_players`, corrected from an earlier draft of this spec.** Writing
   `villagers(count) = count - specials - wolves(count)`, `wolves(count)` is
   `max(1, div(count, 4))` in automatic mode: this is non-decreasing as
   `count` grows (each extra seat adds one villager, except at the
   four-player boundaries where it also adds one more wolf, netting to
   zero — never negative). So within any reachable range of seat counts, the
   *most* villager-favourable, easiest-to-satisfy count is the *largest* one
   reachable. When `max_players` is set, that largest reachable count is
   `max_players` itself — nothing can seat more than that — so if
   `specials + wolves(max_players) > max_players`, the combination fails at
   every reachable seat count and can never work; Rule 7 rejects it
   edit-time. When `max_players` is `nil` (no cap), there is no such ceiling
   to check — arbitrarily many players could still join, and `villagers`
   grows without bound — so automatic mode has no edit-time bound in that
   case, and infeasibility is caught only at start (Rule 9), against the
   real seated count. The same reasoning covers manual mode: its wolf count
   is fixed regardless of `count`, so it fails at every reachable count, or
   none, purely based on whether it fits at `max_players`; with no
   `max_players`, more players can always be added, so manual mode has no
   edit-time bound either in that case.
3. **`max_players` applies to `:join` and to `add_player` alike (Decision 6,
   decided 2026-09-13: everyone counts).** It still does not, and
   structurally cannot, apply to `Game`'s own `:create` action (which
   auto-seats the owner and accepts a `:players` argument): `max_players` is
   not one of `:create`'s accepted attributes (see Out of scope), so it is
   always `nil` at the moment any game is created, and Rules 11/16's check
   never fires when `max_players` is `nil`. Rule 15 explains why this makes
   the shared check a structural no-op for `Game.create`'s own seeding
   rather than a live rejection, with the grep evidence (under "Existing
   tests this will break") that no existing test relies on the opposite.
   `start` never checks `max_players` either. **`:update_settings` may no
   longer lower `max_players` below the game's current seat count** —
   Decision 7, decided 2026-09-13, reverses what this assumption originally
   accepted; see Rules 17 and 18. **Revised 2026-09-13:** the race this
   assumption previously accepted for `:join` —
   two joins at the same instant together taking a game one past
   `max_players` — is closed for both `:join` and `add_player`; see Rule 15
   for the mechanism.
4. **`min_players`/`max_players` must be positive integers** (`>= 1`) when
   set. The bead does not say this explicitly, but a minimum or maximum of
   zero or negative is meaningless, and other `Game` attributes already carry
   this kind of basic sanity constraint (e.g. `name`'s `min_length: 1`).
5. **One existing test breaks and needs a one-line fix**, not a new bead: see
   "Existing tests this will break" under Acceptance.

## Goal

The owner decides a game's role distribution and player bounds instead of
having them hardcoded. A `Game` carries these as attributes, defaulting to
exactly qss.3's behaviour (one seer, one bodyguard, one hunter, automatic
wolf count, minimum 5, no maximum). The owner may change them at any time
while the game is in `:lobby`, through a dedicated owner-only action;
changing them once the game has started is refused. Two independent
checks keep the settings sane: editing refuses a combination that could
never produce a valid game no matter how many players join, and starting
refuses a configuration the players actually seated cannot satisfy, saying
which part does not fit.

## Rules

1. `Game` gains seven new attributes, each defaulting to qss.3's current
   behaviour: `role_distribution_mode` (`:automatic` | `:manual`, default
   `:automatic`), `manual_werewolf_count` (integer, nullable, default `nil`,
   read only in manual mode), `seer_enabled` / `bodyguard_enabled` /
   `hunter_enabled` (booleans, each default `true`), `min_players` (integer,
   default 5), `max_players` (integer, nullable, default `nil` meaning no
   cap). A freshly created game, with none of these touched, has exactly
   these seven values. The five that always have a value
   (`role_distribution_mode`, `seer_enabled`, `bodyguard_enabled`,
   `hunter_enabled`, `min_players`) are `allow_nil? false`, so
   `:update_settings` cannot write `nil` to them and the migration creates
   them as `NOT NULL` columns. A `nil` `min_players` would otherwise make
   `seated >= nil` always false and leave the game unable to start.
   `manual_werewolf_count` and `max_players` stay nullable.
2. A new update action, `:update_settings` (`Games.update_game_settings`),
   accepts exactly these seven attributes (a caller may supply any subset).
   Called by anyone other than the game's own owner, it is rejected on
   `:owner_id` — the same outcome and mechanism (`ActorIsOwner`) as `start`
   already uses for the same reason.
3. `:update_settings` is rejected once the game has left `:lobby` (`field:
   :state`); it succeeds in `:lobby` regardless of which subset of the seven
   attributes is supplied. Express this with Ash's built-in
   `validate attribute_equals(:state, :lobby)`, not a new validation module.
4. `:update_settings` rejects a non-positive `min_players` (`field:
   :min_players`) and rejects a non-positive `max_players` when one is
   supplied (`field: :max_players`); `max_players` left `nil` is not subject
   to this check.
5. `:update_settings` rejects a combination where `min_players` is greater
   than `max_players`, when `max_players` is set (`field: :max_players`); a
   `nil` `max_players` never conflicts with `min_players`.
6. `:update_settings` rejects `manual_werewolf_count` being `nil` or less
   than 1 whenever the resulting `role_distribution_mode` is `:manual`
   (`field: :manual_werewolf_count`). The same nil/low value is accepted
   when the resulting mode is `:automatic`, since it is not read there.
7. `:update_settings` rejects, whenever `max_players` is set, a combination
   where the count of enabled specials (0–3, from `seer_enabled`/
   `bodyguard_enabled`/`hunter_enabled`) plus a wolves figure exceeds
   `max_players` (`field: :max_players`). The wolves figure is
   `manual_werewolf_count` when the resulting `role_distribution_mode` is
   `:manual`, or `max(1, div(max_players, 4))` — Rule 8's own formula
   evaluated at the ceiling `max_players` — when the resulting mode is
   `:automatic` (Assumption 2 justifies checking automatic mode at exactly
   `max_players`). When `max_players` is `nil` (no cap), this check does not
   apply to either mode — there is no ceiling to fail against, so
   infeasibility is caught only at start (Rule 9).
8. `WerewolfAsh.Games.Game.RoleAssignment.composition/2(player_count,
   settings)` replaces `composition/1`, **and drops `composition/1`'s
   `player_count >= 5` guard** (`lib/werewolf_ash/games/game/role_assignment.ex:20`)
   — this bead lets `min_players` go below 5 (Rule 1/4), so `start` can reach
   `DealRoles` with fewer than 5 actual seats, and `composition/2` must
   handle whatever seat count Rule 9 has already confirmed fits, with no
   built-in floor of its own. `settings` is anything exposing
   `role_distribution_mode`, `manual_werewolf_count`, `seer_enabled`,
   `bodyguard_enabled`, `hunter_enabled` (a `Game.t()` satisfies this; no
   other field is read). It builds the specials list from the three enabled
   flags (0 to 3 of `:seer`, `:bodyguard`, `:hunter`, each at most once);
   computes the werewolf count as `manual_werewolf_count` when the mode is
   `:manual`, or `max(1, div(player_count, 4))` — qss.3's own formula,
   unchanged, floor and all — when `:automatic`; and fills every remaining
   seat with `:villager`. `manual_werewolf_count` is never read in
   `:automatic` mode. (Rule 9 guarantees `specials + werewolf_count <=
   player_count` before this ever runs, and werewolf_count is always at
   least 1, so `player_count >= 1` in practice — but `composition/2` itself
   enforces no minimum; that enforcement lives entirely in Rule 9.)
9. `start` rejects when `length(specials) + werewolf_count` (Rule 8's
   numbers, evaluated at the actual number of seated players for automatic
   mode) is greater than the actual number of seated players (`field:
   :players`); equal is allowed (zero villagers is a valid, if grim, game).
   No roles are dealt when this fires.
10. `start`'s existing minimum-seat validation
    (`Game.Validations.MinimumPlayers`) reads the game's own configured
    `min_players` instead of a literal 5 (`field: :players`, unchanged); at
    the default of 5 its behaviour is identical to today's.
11. `join` is rejected once the game already has `max_players` seated
    players (`field: :join_code`, the same field `GameInLobby` already uses
    on this action); it succeeds at any lower seated count, and this check
    never fires when `max_players` is `nil`. This holds even when two
    `:join` calls for the same game race at the same instant: the two calls
    can never together seat more than `max_players` — Rule 15 gives the
    mechanism that makes this true.
12. A game whose settings are never touched after creation deals roles,
    enforces its minimum, and accepts joins exactly as qss.3 did before this
    bead — automatic mode, all three specials enabled, minimum 5, no
    maximum.
13. `:update_settings` sets `require_atomic? false`, exactly as `:start`
    already does (`lib/werewolf_ash/games/game.ex:69`). `ActorIsOwner`
    implements only `validate/3`, so Ash's generated default `atomic/3`
    returns `{:not_atomic, ...}` for it
    (`deps/ash/lib/ash/resource/validation.ex:236-238`); the Rules 4–7
    consistency validations are custom `Ash.Resource.Validation` modules
    reading resulting attribute values the same way, so they have the same
    shape. Left atomic, `mix compile --warnings-as-errors` fails on the
    `VerifyActionsAtomic` warning this produces, and at runtime the action
    would return `Ash.Error.Framework.MustBeAtomic` instead of running
    (`deps/ash/lib/ash/actions/update/update.ex:243-254`).
14. If, at implementation time, `Game` already has an
    `authorizers: [Ash.Policy.Authorizer]` declaration (i.e. `werewolf_ash-27w.2` has already
    merged), `:update_settings` also gets an owner-only policy mirroring
    whatever policy `:start` carries by then, with its own test using a
    non-owner actor. If `Game` has no policy authorizer yet, `:update_settings`
    relies on `ActorIsOwner` alone (Rule 2), exactly as `:start` does today,
    and `werewolf_ash-27w.2` adds the matching policy when it lands
    (Assumption 1). Either way, `ActorIsOwner` stays in place — this rule
    only adds to it, never replaces it.

15. The check in Rules 11 and 16 is the same `Ash.Resource.Validation`
    (naming the coder's choice, e.g.
    `WerewolfAsh.Games.Player.Validations.GameNotFull`), **declared twice on
    `Player`** — once on `:join`, once on the primary `:create` action Rule
    16 attaches it to (the one `add_player` uses) — each with its own
    `before_action?: true` and its own `field:`, mirroring how `GameInLobby`
    is already declared twice on this same resource with a different
    `field:` per action (`field: :join_code` on `:join`, `field: :game_id`
    on `:destroy`; `lib/werewolf_ash/games/player.ex:49,61`):
    `validate {GameNotFull, field: :join_code}, before_action?: true` on
    `:join`; `validate {GameNotFull, field: :game_id}, before_action?: true`
    on `:create`. That option defers running the validation into an
    `Ash.Changeset.before_action` hook instead of running it while the
    changeset is being built
    (`deps/ash/lib/ash/resource/validation.ex:161-166` documents the option;
    the dispatch that wraps a `before_action?: true` validation in
    `before_action(changeset, fn changeset -> ... do_validation(...) end)`
    is at `deps/ash/lib/ash/changeset/changeset.ex:4242-4249`).

    **The validation always takes the lock first, unconditionally, before it
    ever looks at `max_players`** — it reloads the game with a row lock —
    `Games.get_game(game_id, authorize?: false, lock: :for_update)` — and
    only *then* reads that locked row's own `max_players` to decide whether
    Rules 11 and 16's "never fires when `max_players` is `nil`" applies.
    Deciding nil-ness from anything read earlier, or from any source other
    than this same locked row, would reopen the exact race Decision 1 exists
    to close: with an `:update_settings` call locking the game, counting N
    seated players, and writing `max_players = N` (Rule 17 allows equal) but
    not yet committed, a `:join`/`add_player` that checked `max_players`
    before taking any lock of its own would, under READ COMMITTED, still see
    the pre-update value — `nil`, if the game had no cap before — conclude
    there is nothing to enforce, and insert a seat the not-yet-committed cap
    was never given the chance to block. Locking first and reading
    `max_players` off that same locked row instead forces whichever of the
    two calls reaches the row second to wait for the first to commit or roll
    back, so it always sees the first's actual effect before making its own
    decision — see Rule 18 for `:update_settings`'s own side of this same
    interaction. Only once the locked read comes back, and only if its
    `max_players` is not `nil`, does the validation go on to count seated
    players and compare the count to `max_players`. `Games.get_game/1,2`'s
    generated code interface passes
    an unrecognised `lock:` option straight through to the underlying
    `Ash.read_one/2` call rather than dropping it
    (`deps/ash/lib/ash/code_interface.ex:2090-2100` only pulls out
    `:query`/`:actor`/`:tenant`/`:authorize?`/`:tracer`/`:context`/`:scope`
    into the query's own opts, leaving `lock:` in the `opts` that
    `read_get_act/3`, `deps/ash/lib/ash/code_interface.ex:2143-2151`,
    forwards to `Ash.read_one/2`, which reads `Keyword.get(opts, :lock)` the
    same way `Ash.get/3` does at `deps/ash/lib/ash.ex:2459`).
    `AshPostgres.DataLayer` turns `lock: :for_update` into `SELECT ... FOR
    UPDATE OF` the games table (`deps/ash_postgres/lib/data_layer.ex:709`,
    `4263-4271`) — the same primitive Ash's own built-in
    `Ash.Resource.Change.GetAndLockForUpdate` uses for update/destroy
    actions (`deps/ash/lib/ash/resource/change/get_and_lock_for_update.ex:
    17-26`); this bead needs the same effect from a `create` action instead,
    where `changeset.data` is the new `Player`, not the `Game`, so it locks
    the `Game` by `game_id` directly rather than reusing that built-in
    change.

    **`Game.create`'s own seeding routes through this exact same `:create`
    action, not a separate path.** The owner's seat (from `SeatOwner`) and
    every entry in the `:players` argument are created by
    `manage_relationship(:players, type: :create)`, whose bare `:create`
    type resolves to `Player`'s *primary* create action —
    `Ash.Changeset.ManagedRelationshipHelpers.sanitize_opts/2`,
    `deps/ash/lib/ash/changeset/managed_relationship_helpers.ex:39-41`,
    calls `primary_action_name!(relationship.destination, :create)` for the
    bare `:create` type — the very action Rule 16 attaches the check to. So
    the check *is* wired onto `Game.create`'s seeding too, which is what
    makes Decision 6 ("everyone counts") true rather than aspirational. In
    practice it can never *reject* anything there today: `max_players` is
    not one of `Game`'s `:create`-accepted attributes (see Out of scope), so
    it is always `nil` for a game that has not finished being created, and
    the check never fires when `max_players` is `nil` (Assumption 3). See
    "Existing tests this will break" under Acceptance for the grep evidence
    that no existing test seats enough players through `Game.create`,
    `add_player`, or the shared `player()` test generator for this to matter
    even hypothetically.

    This only closes a race if the lock and the later `Player` insert share
    one database transaction, and they do for both declarations
    identically. `:join` and `:create` are both `create`-type actions,
    `transaction?: true` by default
    (`deps/ash/lib/ash/resource/actions/create.ex:32`), and registering any
    `before_action` hook forces `Ash.Changeset.with_hooks` to actually open
    that transaction regardless of the data layer's own preference:
    `prefer_transaction?` is computed as `data_layer_prefers_transaction?`
    only when every hook list, including `before_action`, is empty, and
    forced to `true` otherwise
    (`deps/ash/lib/ash/changeset/changeset.ex:4644-4653`). That distinction
    matters specifically in this repo, whose own `Repo` turns the data
    layer's preference off — `def prefer_transaction?, do: false` at
    `lib/werewolf_ash/repo.ex:10-12`, to avoid opening transactions actions
    don't need — so without a registered `before_action` hook, either action
    would keep running its `INSERT`(s) un-transacted, same as today; adding
    this validation is what first gives both a real transaction to hold the
    lock across (true for every call to either action once this bead lands,
    capped game or not — harmless, since nothing asserts on either action's
    transaction-internals today, only on the final `Player`/`Game` state).
    A second, concurrent call to either action against the same game then
    blocks on the same `SELECT ... FOR UPDATE` until the first transaction
    commits or rolls back, then re-reads the seat count — which by then
    includes the first call's committed `Player` row(s) — before deciding
    whether a seat is still open. If the validation fails, the changeset is
    invalid and the transaction rolls back without inserting anything or
    leaving the lock held (`deps/ash/lib/ash/changeset/changeset.ex:
    4981-4983`, `4672-4686`). This is what makes Rules 11 and 16's
    guarantees hold under a race, not just sequentially.

    **No test in this bead's suite can catch a missing lock or a missing
    `before_action?: true` on either declaration.** `mix test`'s sandbox
    (`test/support/data_case.ex`) gives one test process one physical
    connection running one already-open outer transaction
    (`deps/ecto_sql/lib/ecto/adapters/sql/sandbox.ex`, "Collaborating
    processes"); a second Elixir process only reaches the database at all
    once explicitly allowed onto that same connection, at which point it is
    in the very same session and the very same transaction as the first, so
    a `SELECT ... FOR UPDATE` issued from one can never block behind the
    other — there is no second session left to block against. Two processes
    each given their own separate sandbox checkout instead get two
    independent transactions that never see each other's writes, since the
    sandbox specifically stops either one from committing to the real
    database — so the second could not find the first's uncommitted `Game`
    row either, race or no race. (A genuine two-session test is possible
    with `Ecto.Adapters.SQL.Sandbox.checkout(repo, sandbox: false)`, which
    commits for real and needs its own manual cleanup; nothing in this
    codebase does that today, and this bead does not add it — see Out of
    scope.) Per the project's own convention for exactly this situation
    (CLAUDE.md's reactor-`async?` rule), **the code-reviewer verifies this
    rule by reading the diff, not by running the suite**: confirm both
    validations — on `:join` and on `:create` — are declared with
    `before_action?: true`; confirm each opens with a fresh
    `Games.get_game(..., lock: :for_update)` rather than reusing an
    already-loaded `Game`; confirm **the lock is taken unconditionally,
    before `max_players` is read at all — never gated behind an earlier,
    unlocked check of whether the game is even capped**; confirm the
    seated-player count each compares against `max_players` is read only
    after that call returns, never cached from before it; and confirm
    nothing later in either action's pipeline reads or writes this game's
    `Player` rows outside that same hook's transaction. Rules 11 and 16's
    ordinary functional cases — below cap, at cap, uncapped, for each
    action — still get normal, deterministic, sequential tests (see
    Acceptance).
16. `add_player` (`Player`'s primary `:create` action, `Games.add_player/2,3`)
    is rejected once the game already has `max_players` seated players, by
    the same check and count as Rule 11 (`field: :game_id` — the field
    `add_player`'s own `game_id`/`user_id` arguments name; it takes no
    `join_code`). It succeeds at any lower seated count and never fires when
    `max_players` is `nil`, exactly mirroring Rule 11; Rule 15 gives the
    shared mechanism. This is the one place Decision 6 ("everyone counts")
    changes live behaviour: unlike `:join`, `add_player` carries no
    `GameInLobby` check today and can be called at any time, including after
    `:update_settings` has already set `max_players` on a game that is now
    full — without this rule, `add_player` would be a standing bypass of a
    cap `:join` otherwise enforces strictly.
17. `:update_settings` refuses to set `max_players` below the game's current
    seated-player count (`field: :max_players`); setting it exactly equal to
    the seated count is allowed, and `max_players` left `nil` is never
    subject to this check (the same nil carve-out Rule 4 already gives the
    other `max_players` checks). The refusal happens before any attribute is
    written: the whole `:update_settings` call fails, nobody is removed from
    the game, and none of the other six settings change either, even if they
    were supplied together in the same call (Decision 7).
18. Rule 17's check is race-safe against a concurrent `:join`/`add_player`
    on the same `Game` row, using the identical technique Rule 15 already
    establishes: a new `Ash.Resource.Validation` (naming the coder's choice,
    e.g. `WerewolfAsh.Games.Game.Validations.MaxPlayersNotBelowSeated`),
    declared on `:update_settings` with `before_action?: true` —
    `validate {MaxPlayersNotBelowSeated, field: :max_players},
    before_action?: true`. `:update_settings` already sets `require_atomic?
    false` (Rule 13), which a `before_action?: true` validation on an update
    action requires: `update` actions default `require_atomic?` to `true`
    (`deps/ash/lib/ash/resource/actions/update.ex:20`), and a
    `before_action?: true` validation cannot be run atomically —
    `{:not_atomic, "before_action? validation ... cannot be run atomically.
    To use before_action? validations, set require_atomic? false ..."}`
    (`deps/ash/lib/ash/changeset/changeset.ex:1180-1183`); Rule 13 already
    puts `:update_settings` on the non-atomic path this needs.

    Only when the resulting `max_players` is set does the validation do
    anything — a `nil` result never fires it (Rule 17), and this one *is*
    safe to decide before taking any lock, unlike Rule 15's `GameNotFull`.
    The two are not the same question: this validation is asking what *this
    transaction's own changeset* is about to write, a fact this transaction
    already fully controls and that no concurrent transaction can change out
    from under it, so reading `Changeset.get_attribute(changeset,
    :max_players)` before locking is fine. `GameNotFull` (Rule 15) is asking
    whether the `Game` row *already has* a cap — a fact that lives in
    another transaction's possible in-flight write, which is exactly why it
    cannot trust an unlocked answer and must lock first, unconditionally,
    before it ever reads `max_players` (see Rule 15's own note on this).
    When this validation's resulting `max_players` is not `nil`, it reloads
    the game with a row lock — `Games.get_game(game_id,
    authorize?: false, lock: :for_update)`, the exact call Rule 15 uses —
    **before** counting seated players, not after. That ordering is what
    makes this race-safe, and it is the only thing that does: `:update_settings`
    is itself an `update` action, `transaction?: true` by default
    (`deps/ash/lib/ash/resource/actions/update.ex:32`, the same default Rule
    15 already cites for `create` actions at `create.ex:32`), so the `UPDATE
    games SET ...` statement Ash eventually issues will lock this row
    regardless of anything this bead adds — but only once it runs, which is
    after every `before_action` hook has already completed. If the seated
    count were read any earlier — as a plain eager validation, running while
    the changeset is still being built, well before any lock on this row
    exists — a concurrent `:join`/`add_player` could commit a brand-new seat
    in the gap between that read and the eventual `UPDATE`, and this check
    would have approved a `max_players` that was already violated the
    instant it landed; relying on the implicit lock the final `UPDATE`
    itself takes would be too late, since by then the comparison has already
    happened. Taking the lock first, inside the same `before_action` phase
    the eventual write itself runs in, closes that gap: a concurrent
    `:join`/`add_player` racing this call blocks on the identical `SELECT
    ... FOR UPDATE` (Rule 15) until whichever transaction got there first
    commits or rolls back, so whichever side goes second always sees the
    other's already-committed effect — either the new seat this check must
    count, or the new `max_players` that check must respect. This is Rule
    15's pattern applied to `Game`'s own row instead of a foreign one:
    `changeset.data` here already *is* the `Game` being updated, but the
    validation still issues a fresh `Games.get_game(..., lock: :for_update)`
    rather than reusing `changeset.data`, because `changeset.data` was
    loaded before this action began and carries no lock of its own.

    **No test in this bead's suite can catch a missing lock here either, for
    the same reason Rule 15 gives** (`mix test`'s sandbox cannot reproduce
    two genuinely concurrent sessions — see Rule 15's own explanation, which
    applies unchanged). **The code-reviewer verifies this rule alongside
    Rule 15's, by reading the diff**: confirm this validation is declared
    with `before_action?: true`; confirm it opens with a fresh
    `Games.get_game(..., lock: :for_update)` before counting, never after;
    confirm the seated-player count it compares against the resulting
    `max_players` is read only once that call returns; and confirm
    `:update_settings` still sets `require_atomic? false` (Rule 13), without
    which declaring this validation would fail to compile at all. Rule 17's
    ordinary functional cases — below the seated count, equal to it, and
    `nil` — still get normal, deterministic, sequential tests (see
    Acceptance).
19. `add_player`'s declaration of `GameNotFull` (Rule 15) can now discover a
    nonexistent `game_id` before the insert ever reaches the database,
    because its locked reload — `Games.get_game(game_id, authorize?: false,
    lock: :for_update)` — returns `{:error, %Ash.Error.Query.NotFound{}}`
    for a `game_id` that names no row: `Games.get_game/1,2`'s
    `not_found_error?` code-interface option defaults to `true`
    (`deps/ash/lib/ash/resource/interface.ex:324-329`), and `get_by: [:id]`
    is what makes `:get_game` a `get?: true` interface in the first place
    (`deps/ash/lib/ash/resource/interface.ex:31-33`); the not-found path
    itself is `deps/ash/lib/ash/code_interface.ex:2152-2154`. When that
    happens, `GameNotFull` adds an error on `:game_id` — `field: :game_id,
    message: "does not exist"` — the same field, and the same wording style,
    `WerewolfAsh.Games.Player.Changes.ResolveGameByJoinCode` already uses
    for its own equivalent case
    (`lib/werewolf_ash/games/player/changes/resolve_game_by_join_code.ex:
    24-28`, `field: :join_code, message: "does not match any game"`) —
    rather than letting a nonexistent id fall through to whatever error
    Postgres's own foreign-key constraint on `players.game_id` would
    otherwise have produced at insert time. `:join`'s declaration of the
    same validation can never take this branch: `ResolveGameByJoinCode`
    already guarantees `game_id` names a real game before `:join`'s
    changeset is even valid, and an invalid changeset never reaches any
    `before_action` hook at all (`with_hooks` short-circuits on
    `changeset.valid? == false` before running any of them,
    `deps/ash/lib/ash/changeset/changeset.ex:4635-4637`) — only
    `add_player`, whose `:game_id` is a bare caller-supplied argument with
    no such resolution step first, can reach this path.

## Out of scope

- The vote-deadline offset (`werewolf_ash-qss.15`). Its NOTES say it appends
  to this bead's settings or shares a migration if worked together; this
  spec adds none of it.
- Exposing `update_game_settings` (or any of these new attributes) over
  GraphQL — that is `werewolf_ash-27w.3`, which depends on `27w.2` (policies)
  and has not started.
- Adding an `authorizers: [Ash.Policy.Authorizer]` declaration to `Game` from scratch. That is
  `werewolf_ash-27w.2`'s job; this bead only adds a policy alongside it
  (Rule 14) when that extension is already present at implementation time,
  and otherwise relies on `ActorIsOwner` alone (Assumption 1).
- Accepting any of the seven new attributes on `Game`'s `:create` action, or
  seeding them through `add_player`/the `:players` argument. They are set
  only via `:update_settings`, after creation, while still in `:lobby`.
  Touching `:create`'s `accept` list would also force pinning new fields in
  the `game()` test generator (see its own doc comment on why accepted
  attributes need pinning) — an avoidable expansion of this bead's diff.
- Making `max_players` reachable during `Game.create` itself (e.g. adding it
  to `:create`'s accept list, so a game could be born already at or over a
  cap given to it at birth). Decision 6 only asks for every seat that can
  already exist to count toward a cap set after the fact; it does not ask
  for a new way to set `max_players` at creation. `Game.create`'s accept
  list, its `:players` argument, and its interaction with `SeatOwner` stay
  exactly as they are (Rule 15 explains why the shared check is a no-op
  there regardless).
- `werewolf_ash-qss.18`'s target-validity rules (target alive, cross-game
  actor/target/phase checks, consecutive-protect) — untouched here.
- `werewolf_ash-qss.5` (`EndDay` lynch reactor) and `werewolf_ash-qss.6`
  (night aftermath) — untouched here.
- `werewolf_ash-qss.20`'s two test-assertion nits in `action_test.exs` — that
  file is read here for context only; its `started_game/0` is unaffected
  (see Acceptance) and is not edited by this bead.
- Renaming `MinimumPlayers`, its `field: :players`, or its existing test
  file's structure — only its source of truth for the threshold changes.
- Adding `WerewolfAsh.Games.Game.RoleDistributionMode` (or any other new
  enum this bead introduces) to `test/werewolf_ash/games/enum_docs_test.exs`.
  That list is hand-curated and does not include the existing `Winner` enum
  either; follow that precedent and leave it alone.
- Making `:join`'s existing `GameInLobby` check race-proof against a game
  finishing its lobby between that eager check and Rule 15's locked section
  later in the same call. That race predates this bead, is not one the
  owner asked to close here, and is not touched by Rule 15 (which is
  declared as a separate validation, not a change to `GameInLobby` itself);
  leave `GameInLobby` exactly as it is.
- A genuine two-session concurrency test for Rule 15, e.g. via
  `Ecto.Adapters.SQL.Sandbox.checkout(repo, sandbox: false)`. Rule 15
  explains why the ordinary sandbox can't exercise the race and specifies
  code review, not a test, as how the locking mechanism itself is checked;
  introducing a real, uncontained, manually-cleaned-up test connection for
  one bead is out of scope.

## Acceptance

- `WerewolfAsh.Games.Game.RoleAssignment.composition/2` — direct unit tests:
  qss.3's exact formula reproduced under default settings at the existing
  boundary cases (5, 7, 8 players); manual mode's count used verbatim
  regardless of `player_count`; each of the three specials independently
  on and off; all three specials off at once (Rule 8). Because the
  `player_count >= 5` guard is gone (Rule 8), also cover a count below 5
  (e.g. 4 seats, all specials enabled, automatic mode) and, separately, a
  count below 4 with `max(1, div(count, 4))` and bare `div(count, 4)` giving
  different answers — e.g. 2 seats, no specials enabled, automatic mode:
  `div(2, 4) == 0` but the rule requires the `max(1, ...)` floor, so exactly
  1 werewolf and 1 villager, never 0 werewolves.
- `WerewolfAsh.Games.Game.Validations.MinimumPlayers.validate/3` — direct
  unit test that a non-default configured `min_players` (not just 5) is
  read and enforced (Rule 10), including a value below 5; the two existing
  tests (pass at the configured minimum, fail below it) keep working
  unchanged since the default is still 5.
- The new start-time validation (naming is the coder's choice, e.g.
  `Game.Validations.RoleCompositionFits`) — direct unit tests: exact fit
  (specials + wolves == seated count) passes; short by one fails; one
  automatic-mode case and one manual-mode case (Rule 9); one case with an
  actual seated count below 5 that fits exactly (pairing with Rule 8's
  guard removal, e.g. `min_players` 4, all specials enabled, 4 actually
  seated).
- The new settings-consistency validation(s) backing `:update_settings`
  (naming is the coder's choice; may be one module or several, following
  this codebase's existing one-validation-per-rule style) — direct unit
  tests per Rules 4, 5, 6 and 7, each with its passing counterpart; Rule 7's
  automatic-mode case (evaluated at `max_players`) is a separate test from
  its manual-mode case, not just a variation of it.
- `Games.update_game_settings/1,2,3` — code-interface tests: owner accepted,
  non-owner rejected (Rule 2); if `Game` already carries a policy authorizer
  at implementation time, a non-owner-via-policy rejection too (Rule 14);
  accepted in `:lobby`, rejected once started (Rule 3); a partial update
  (only one of the seven fields) leaves the others at their prior values;
  passing `nil` for any of the five non-nullable settings is rejected
  (Rule 1); passing an attribute outside the seven, for example `name`, is
  rejected (Rule 2);
  the full Rule 4–7 matrix reachable through the action, not just through
  the validation modules directly; refused when the supplied `max_players`
  is below the game's current seated count (`field: :max_players`), accepted
  when set exactly equal to it, and unaffected (never refused on this
  ground) when `max_players` is left `nil` — Rule 17, with a check that
  nobody was removed and the game's other settings are unchanged after a
  refusal.
- `WerewolfAsh.Games.Player.Validations.GameNotFull.validate/3` (naming is
  the coder's choice) — direct unit tests: accepted below `max_players`,
  refused at `max_players`, and unaffected (never refused) when
  `max_players` is `nil` — the same three cases Rules 11/16 need through
  each action, pinned directly on the validation's own contract; plus the
  not-found case (Rule 19): a `game_id` naming no row is rejected on
  `:game_id`.
- The new `MaxPlayersNotBelowSeated` validation (naming the coder's choice)
  backing Rule 17 — direct unit tests for the same three cases (below the
  seated count, equal to it, `nil`). Rule 18's locking mechanism has no
  passing/failing test that distinguishes it from an unlocked, racy version
  of the same check (that rule explains why) — the code-reviewer checks it
  by reading the diff, per Rule 18's checklist, alongside Rule 15's.
- `Games.join_game/2,3` — tests for Rule 11: accepted below `max_players`,
  refused at `max_players`, and unaffected (never refused) when
  `max_players` is `nil`.
- `Games.add_player/2,3` — tests for Rule 16: accepted below `max_players`,
  refused at `max_players`, and unaffected (never refused) when
  `max_players` is `nil` — the same three cases as `Games.join_game/2,3`,
  through the other action that can seat a player. Rule 15's locking
  mechanism, shared by both actions, has no passing/failing test that
  distinguishes it from an unlocked, racy version of the same check (that
  rule explains why) — the code-reviewer checks it by reading the diff, per
  Rule 15's checklist.
- End to end: through the code interface only (`Games.create_game!` →
  `Games.update_game_settings!` with manual mode, a chosen wolf count, and
  the seer disabled → seat enough players via `Games.join_game!`/
  `add_player!` → `Games.start_game!`), the dealt roles have no seer, the
  exact configured wolf count, and villagers filling the rest.
- `mix ash.codegen <name>` run and its migration + snapshot committed;
  `mix ash.codegen --check`, `mix compile --warnings-as-errors`, `mix lint`
  and `mix test` all clean.

### Existing tests this will break

Grep run: `grep -rn "generate_many(player(game_id: game.id)," test`

```
test/werewolf_ash/games_test.exs:147:      generate_many(player(game_id: game.id), 4)
test/werewolf_ash/games_test.exs:335:      generate_many(player(game_id: game.id), 2)
test/werewolf_ash/games/action_test.exs:21:    generate_many(player(game_id: game.id), 4)
test/werewolf_ash/games/reactors/resolve_win_test.exs:19:    generate_many(player(game_id: game.id), 4)
test/werewolf_ash/games/game/changes/deal_roles_test.exs:14:      generate_many(player(game_id: game.id), 4)
test/werewolf_ash/games/game/changes/deal_roles_test.exs:32:      generate_many(player(game_id: game.id), 4)
test/werewolf_ash/games/game/validations/minimum_players_test.exs:13:      generate_many(player(game_id: game.id), 4)
test/werewolf_ash/games/game/validations/minimum_players_test.exs:22:      generate_many(player(game_id: game.id), 2)
```

Every occurrence of `4` seats 5 total with the generator's auto-seated owner
(default `min_players`, default full specials) — Rule 9's new check computes
`specials(3) + wolves(max(1, div(5,4))=1) = 4 <= 5`, fits, so none of these
are affected: `games_test.exs:147` (`ready/1`), `action_test.exs:21`
(`started_game/0`), `resolve_win_test.exs:19` (`start/1`),
`deal_roles_test.exs:14,32` (calls `DealRoles.change/3` directly, never
`start`, so Rule 9 cannot fire there regardless). `minimum_players_test.exs`'s
two occurrences (line 13 and 22) call `MinimumPlayers.validate/3` directly as
a unit test, never through the `:start` action, so Rule 9's separate
validation module never runs alongside it either — both stale-free.

**`games_test.exs:335` is stale and must change.** That test, "requires at
least 5 seated players" (lines 332–344), seats the auto-seated owner plus 2
more (3 total) and asserts `Games.start_game(game, %{}, actor: owner)`
returns `{:error, %Ash.Error.Invalid{errors: [error]}}` — a single error —
going on to pattern-match that one error as
`%Ash.Error.Changes.InvalidChanges{fields: [:players]}`. With Rule 9 added,
3 seated players ALSO fails the new composition-fits check
(`specials(3) + wolves(max(1, div(3,4))=1) = 4 > 3`), and Ash validations run
regardless of an already-invalid changeset unless a validation sets
`only_when_valid?: true` (default `false` — see
`deps/ash/lib/ash/resource/validation.ex:147-151`), so both `MinimumPlayers`
and the new validation add their own error to the same changeset. The test's
`errors: [error]` single-element match no longer matches a two-element list,
and the whole assertion raises a `MatchError` before the field check is even
reached.

The fix is one line: change `generate_many(player(game_id: game.id), 2)` to
`generate_many(player(game_id: game.id), 3)` at line 335 (4 total seated).
At 4 seats, `specials(3) + wolves(max(1, div(4,4))=1) = 4 <= 4` fits exactly,
so Rule 9 no longer fires there; only `min_players` (still 5, default)
remains violated, restoring the single-error shape the test already asserts.
No other line in this test needs to change.

**`role_assignment_test.exs`'s calls are also stale, in shape only.** Grep:
`grep -n "RoleAssignment.composition(" test/werewolf_ash/games/game/role_assignment_test.exs`

```
test/werewolf_ash/games/game/role_assignment_test.exs:8:      assert RoleAssignment.composition(5) |> Enum.frequencies() ==
test/werewolf_ash/games/game/role_assignment_test.exs:13:      assert RoleAssignment.composition(7) |> Enum.frequencies() ==
test/werewolf_ash/games/game/role_assignment_test.exs:16:      assert RoleAssignment.composition(8) |> Enum.frequencies() ==
test/werewolf_ash/games/game/role_assignment_test.exs:21:      composition = RoleAssignment.composition(11)
```

Once `composition/1` becomes `composition/2` (Rule 8), all four calls are a
compile error (undefined function `composition/1`), not a behaviour change —
each needs a second argument carrying default settings (`:automatic`, all
three specials enabled) to keep asserting the identical qss.3 formula at 5,
7, 8 and 11 players. None of these four existing cases exercise the removed
`player_count >= 5` guard (all are `>= 5` already), so none of their
expected values change, only the call shape. This file gains the new
manual-mode, specials-on/off, and below-5/below-4 cases (see Acceptance)
alongside the arity fix.

`test/werewolf_ash/games/game/changes/deal_roles_test.exs` calls
`DealRoles.change/3` and reads the dealt roles back, never
`RoleAssignment.composition/1,2` directly (confirmed by the grep above,
which shows no `composition(` hit there) — its internal call site inside
`deal_roles.ex` changes, but the test's own assertions are against a
default-settings game, so its expected output (`%{seer: 1, bodyguard: 1,
hunter: 1, werewolf: 1, villager: 1}`) is unchanged. Not stale.

`test/werewolf_ash/games/enum_docs_test.exs` was checked
(`@enum_modules` is a hardcoded list of four unrelated enums and does not
already include the existing `Winner` enum) — a new `Game`-level enum from
this bead has no effect on it either way; see Out of scope.

**No existing `Game.create`-seeding or `add_player` test is affected by
Rule 16 either, despite both now running through the same checked action.**
Grepped for a `:players` argument passed to `create_game`:
`grep -n "players:" test/werewolf_ash/games_test.exs`:

```
test/werewolf_ash/games_test.exs:23:          players: [%{user_id: alice.id}, %{user_id: bob.id}]
test/werewolf_ash/games_test.exs:170:                 players: [%{user_id: nameless.id}]
```

Line 23 (part of the `create_game!` call starting at line 16) seeds 2 extra
players, 3 total with the auto-seated owner; line 170 (part of the
`create_game` call starting at line 165) seeds 1 extra, 2 total, and already
expects an unrelated failure (a nameless co-player, `UserHasName`). Neither
comes close to any plausible cap, and `max_players` cannot be set on this
action regardless (Rule 15, Assumption 3), so neither is affected.

Grepped for `add_player`: `grep -rn "add_player" test lib`:

```
lib/werewolf_ash/games.ex:29:      define :add_player, action: :create, args: [:game_id, :user_id]
test/werewolf_ash/games_test.exs:412:      player = Games.add_player!(game.id, alice.id)
test/werewolf_ash/games_test.exs:429:      Games.add_player!(game.id, alice.id)
test/werewolf_ash/games_test.exs:431:      assert {:error, %Ash.Error.Invalid{errors: [error]}} = Games.add_player(game.id, alice.id)
test/werewolf_ash/games_test.exs:435:      assert %{user_id: user_id} = Games.add_player!(other_game.id, alice.id)
test/werewolf_ash/games_test.exs:442:      assert {:error, %Ash.Error.Invalid{}} = Games.add_player(game.id, alice.id, %{role: :seer})
test/werewolf_ash/games_test.exs:446:      player = Games.add_player!(game.id, generate(user()).id)
test/werewolf_ash/games_test.exs:464:      player = Games.add_player!(game.id, generate(user()).id)
test/werewolf_ash/games_test.exs:476:      Games.add_player!(game.id, generate(user()).id)
test/werewolf_ash/games_test.exs:486:               Games.add_player(game.id, nameless.id)
test/werewolf_ash/games_test.exs:495:      assert %{user_id: user_id} = Games.add_player!(game.id, named.id)
test/werewolf_ash/games_test.exs:503:      assert %{id: alice_player_id} = Games.add_player!(game.id, alice.id)
test/werewolf_ash/games_test.exs:504:      assert %{id: bob_player_id} = Games.add_player!(game.id, bob.id)
test/werewolf_ash/games_test.exs:639:      [alice, bob] = for u <- generate_many(user(), 2), do: Games.add_player!(game.id, u.id)
```

None of these games ever has `max_players` set — this bead is what
introduces the attribute, and every game these tests generate gets its
default, `nil` — so Rule 16's check never fires for any of them; all
stale-free. The pervasive `player()` test generator
(`test/support/generators.ex:55-68`) also creates through this exact same
primary `:create` action and backs every `generate_many(player(game_id:
game.id), N)` call already covered above under "Existing tests this will
break" — same reasoning (no game in the suite has `max_players` set), same
result: unaffected.

## Touches

Advisory only.

- `lib/werewolf_ash/games/game.ex` — seven new attributes, `:update_settings`
  action, its validations.
- `lib/werewolf_ash/games/game/role_distribution_mode.ex` (new) —
  `Ash.Type.Enum`, mirroring `lib/werewolf_ash/games/game/winner.ex`.
- `lib/werewolf_ash/games/game/role_assignment.ex` —
  `composition/1` → `composition/2`.
- `lib/werewolf_ash/games/game/changes/deal_roles.ex` — updated call site.
- `lib/werewolf_ash/games/game/validations/minimum_players.ex` — reads
  `min_players` off the game instead of `@minimum`.
- `lib/werewolf_ash/games/game/validations/` (new modules) — the start-time
  composition-fits check, the settings-consistency checks, and the
  seated-count-vs-`max_players` check backing Rules 17/18, declared with
  `before_action?: true` and locking the `Game` row before counting (same
  technique as the `Player` validations below, applied to `Game`'s own
  row).
- `lib/werewolf_ash/games/player.ex` — `:join` and the primary `:create`
  action (the one `add_player` uses) each gain the max-players check, both
  declared with `before_action?: true` (Rules 15, 16).
- `lib/werewolf_ash/games/player/validations/` (new module) — the
  game-not-full check, shared by both declarations; locks the `Game` row
  before counting seated players (Rule 15).
- `lib/werewolf_ash/games.ex` — `define :update_game_settings, action:
  :update_settings`.
- `priv/repo/migrations/` + `priv/resource_snapshots/repo/games/` — one
  additive migration from `mix ash.codegen`; existing rows keep their
  current behaviour under the new defaults (`priv/repo/migrations/
  20260911190459_add_game_winner.exs` is the precedent for an
  `Ash.Type.Enum` attribute landing as a plain `:text` column).
- Tests: `test/werewolf_ash/games/game/role_assignment_test.exs` (arity fix
  plus new cases), new validation test files alongside the new modules
  (including the `Game`-side `MaxPlayersNotBelowSeated` validation backing
  Rules 17/18), `test/werewolf_ash/games_test.exs` (the one-line fix at line
  335, plus new `update_game_settings`/`join_game`/`add_player` coverage and
  the end-to-end test).
