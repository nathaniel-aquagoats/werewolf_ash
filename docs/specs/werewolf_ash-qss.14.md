# werewolf_ash-qss.14: Owner-configurable game setup: role distribution, optional specials, player bounds

Depends on: none

## For the owner

**What changes.** Game owners will be able to choose how roles are dealt out (automatic by player count, or a manual werewolf count), turn the seer, bodyguard, and hunter roles on or off, and set a minimum and maximum number of players — instead of these being fixed at one seer, one bodyguard, one hunter, an automatic wolf count, and a minimum of 5 with no maximum. These can be changed any time before the game starts, then lock for that game. A game nobody configures behaves exactly as it does today.

**Decisions for you.**
1. How strictly should the maximum player count be enforced? — Options: (a) check it only when someone joins, accepting that two people joining at the exact same instant could both squeeze in one past the cap, and that the cap doesn't apply to the owner's own seat or to players added at game creation; (b) add a stricter, race-proof check now. **Recommended:** (a) — matches how joining already works today, and closing the race is easy to add later without changing anything players see now.
2. Should new games keep today's defaults? — Options: keep them (one seer, one bodyguard, one hunter, automatic wolf count, minimum 5, no maximum) or pick new defaults. **Recommended:** keep today's defaults, so no existing game changes behaviour.
3. What limits apply to the min/max player numbers themselves? — Options: allow any number, including zero or negative (meaningless); or require them to be at least 1. **Recommended:** require at least 1.
4. Can settings be changed after the game starts? — Options: allow changes any time; or lock them once the game starts. **Recommended:** lock them — mid-game rule changes would be confusing and unfair to seated players.
5. Does the order this ships relative to the separate "who can change what" permissions work (`27w.2`) matter? — Options: require this bead to wait for that one; or make it work correctly either order. **Recommended:** either order — only the owner can ever change their game's settings regardless of which lands first.

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
3. **`max_players` applies to `:join` only**, not to `Game`'s own `:create`
   action (which auto-seats the owner and accepts a `:players` argument) or
   to `add_player`. This follows the bead's DESIGN note verbatim: "the join
   path gains the maximum check alongside its existing lobby-state check." A
   game can still technically be created already at or over `max_players`
   through those other paths; nothing here prevents that. `start` never
   checks `max_players` either, and `:update_settings` may lower
   `max_players` below the current seat count. Also accepted for now: the
   join cap reads the seat count and then inserts, so two joins at the same
   instant can take a game one past `max_players`; no database-level
   guarantee is added. **All of this is flagged for the owner to confirm.**
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
    never fires when `max_players` is `nil`.
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
- Enforcing `max_players` anywhere but `:join` (Assumption 3) — not on
  `Game.create`'s auto-seated owner or its `:players` argument, not on
  `add_player`.
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
  the validation modules directly.
- `Games.join_game/2,3` — tests for Rule 11: accepted below `max_players`,
  refused at `max_players`, and unaffected (never refused) when
  `max_players` is `nil`.
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
  composition-fits check and the settings-consistency checks.
- `lib/werewolf_ash/games/player.ex` — `:join` gains the max-players check.
- `lib/werewolf_ash/games/player/validations/` (new module) — the
  game-not-full check.
- `lib/werewolf_ash/games.ex` — `define :update_game_settings, action:
  :update_settings`.
- `priv/repo/migrations/` + `priv/resource_snapshots/repo/games/` — one
  additive migration from `mix ash.codegen`; existing rows keep their
  current behaviour under the new defaults (`priv/repo/migrations/
  20260911190459_add_game_winner.exs` is the precedent for an
  `Ash.Type.Enum` attribute landing as a plain `:text` column).
- Tests: `test/werewolf_ash/games/game/role_assignment_test.exs` (arity fix
  plus new cases), new validation test files alongside the new modules,
  `test/werewolf_ash/games_test.exs` (the one-line fix at line 335, plus new
  `update_game_settings`/`join_game` coverage and the end-to-end test).
