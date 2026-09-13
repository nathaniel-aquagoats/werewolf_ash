# werewolf_ash-27w.2: Policies on Games resources

Depends on: none

## For the owner

**What changes.** Players will only see the games, rosters, and messages they actually have a seat in — a game you're not part of won't show up at all. While a game is in progress and a player is still alive: they see their own role; werewolves also see each other's roles and the pack's kill; the seer sees their own investigation results; the bodyguard sees their own protection; no other role or action detail leaks out. Once a player dies, they become a spectator for the rest of that game and can see everything in it — every role, every kill, investigation, protection, and shot — though they still cannot vote, act, or post. Once a game ends, every role is revealed to everyone who played it. Only the game's owner can start it or change its settings (role mix, specials, player bounds), and every vote, kill, investigation, protection, shot, or chat message a player sends must be sent as themselves, never on someone else's behalf.

**Decisions.**
1. **Decided:** a bodyguard's protection is visible only to the bodyguard who chose it, the same as the wolf kill and the seer's investigation — this closes off telling the wolves whom to avoid once protection can change during the day. Hunter shots stay visible to everyone, the same as votes.
2. **Decided (now just one case of decision 6, below):** a dead werewolf keeps seeing fellow wolves' roles and the pack's kill — nothing in the design narrows it to living wolves only, and it's no longer even a wolf-specific rule: see decision 6.
3. **Decided:** once a game reaches `:finished`, every player's role becomes visible to every seat in that game — built here, not left to the separate follow-up bead that was going to own it.
4. **Decided:** seating another user into a game (useful today for testing/setup) stays open for now; tightening it belongs to the upcoming public sign-up feature.
5. **Decided:** a player can see a fellow player's display name, not their email, in a shared game — this is what lets the roster show names instead of blanks.
6. **Decided:** a dead player is a spectator in an afterlife for the rest of that game — once your own seat has died, you see everything in it: every role, every kill, investigation and protection, not just your own team's. You still cannot vote, act, or post once dead (unchanged).
7. **Decided (asked in chat 2026-09-13, after qss.14 merged):** the same owner-only gate that protects `:start` also protects `:update_settings` (qss.14's owner-configurable role distribution, specials and player bounds) — only the game's owner may change a game's settings, and a non-owner or anonymous caller is refused with the same policy-class error `:start` now gives, not qss.14's own `ActorIsOwner`-validation error. qss.14 landed first, so this bead is the one that adds the policy layer for it (see rules 3a/3b).
8. **Decided (asked in chat 2026-09-13, after the spec review found the promised error was unreachable):** the access rule refuses first. Verified by running it (not by reading it): with `Game.Validations.ActorIsOwner` as an ordinary validation, a non-owner and an anonymous caller both got the validation's own error, never the policy's — the policy never got a chance to run, because Ash checks a changeset's build-time validations before authorization. The fix is a production change, not just a spec correction: on both `:start` and `:update_settings`, `validate ActorIsOwner` becomes `validate ActorIsOwner, before_action?: true`, which defers it to run after authorization instead of before. A non-owner or anonymous caller now gets `Ash.Error.Forbidden` from the policy; the validation stays in place as a backstop for the one path that skips the policy entirely, an internal `authorize?: false` call by a non-owner, which still gets `Ash.Error.Invalid` from the validation. See rules 3a/3b.

**Rule changes.** Add to the settled decisions: "a player may read a game, its roster, and its messages only while seated in it (any role, dead or alive); a player sees only their own role, except werewolves also see each other's, and once a game reaches `:finished` every role is visible to every seat (qss.19 adds the dawn reveal of dead players' roles); the night's kill is visible to werewolves only, an investigation result only to the seer who made it, and a protection only to the bodyguard who chose it; a dead player is a spectator for the rest of that game and sees everything in it regardless of the rules above, though they still cannot vote, act, or post; only the game's owner may start it or change its settings, refused with a policy-class error before either action's own `ActorIsOwner` validation runs; every vote, kill, investigation, protection, shot, or chat message must be submitted as the sender's own seat, never on another player's behalf."

## Assumptions

This bead's description is a short, dense bullet list, and its NOTES fold in
follow-ups from two other beads' reviews. Rather than leave any of it
implicit, this spec resolves every ambiguity below and says so; read this
section before the Rules, since several of these are judgment calls a
different reader could make differently.

1. **qss.3 is merged** (main `e3de03d`). This spec is written against its
   actual shipped shape: `Game.Validations.ActorIsOwner`,
   `Game.Validations.MinimumPlayers`, `Game.Changes.DealRoles`,
   `Game.Changes.SeatOwner` on `Game`'s `:start`/`:create`, and, on `Player`,
   the `:join` action (`Player.Changes.ResolveGameByJoinCode`,
   `Player.Validations.GameInLobby` also guarding `:destroy`) plus
   `create_game`'s auto-seated owner. This bead adds one thing on top of
   qss.3's `:start` (rule 3a) and one explicit policy for `:join` (rule 6),
   and otherwise reads Player/Game exactly as qss.3 shipped them.
2. **"actions only as yourself" scopes to the `Action` resource** (the
   vote/kill/investigate/protect/shoot rows players submit during
   phases), not to `Player` creation or joining. `create_game`'s `players`
   argument and qss.3's `join_game` both accept a `user_id` that is not
   necessarily the caller's own, by qss.3's own design (seeding other users at
   creation time is a kept feature, not a bug) — extending "yourself" to
   `Player` would fight that design and is left alone (see Out of scope).
3. **"wolves see wolf_votes and fellow wolves" (wolf_votes are now the pack's single `:kill` row per night, renamed 2026-09-12) is read as two grants**, not
   one: living-or-dead werewolves see other players' `:werewolf` role (the
   "your own role only" default's one exception), and werewolves also see
   `:kill` `Action` rows. Nothing in the bead's list says a *dead*
   werewolf loses either of these, so this spec does not gate either grant on
   `alive`. (Superseded in effect, not in wording, by the broader
   2026-09-13 "the dead see everything" decision in rules 5/8/Assumption 6:
   a dead werewolf's `:kill`/fellow-role visibility no longer needs this
   assumption to survive death, since *every* dead seat now sees everything
   regardless of role. This assumption still correctly describes the
   *living*-werewolf grant, which is role-conditioned and not superseded.)
4. **Revised 2026-09-13, by owner decision: `:protect` is narrowed the same
   way as `:investigate`; `:vote` and `:shoot` are not.** The previous
   reading of this assumption left all three at the ordinary-game-membership
   baseline, since only `:kill` and `:investigate` were named by the bead's
   description. Superseded: with qss.21 making a bodyguard's protection
   changeable and withdrawable during the day, a `:protect` row visible to
   the whole roster would tell the wolves whom to avoid before night falls —
   the same secrecy problem `:kill` and `:investigate` already avoid, and
   the owner resolved it the same way, in chat before this revision. `:vote`
   and `:shoot` are unaffected: nothing about either changed, and the owner
   was not asked to revisit them. See rule 8 for the narrowed condition.
5. **Every Game/Player/Action action not named by a rule below is left
   exactly as open as it is today** (`authorize_if always()`), rather than
   silently falling into Ash's default-deny the moment an authorizer is
   added. This keeps the bead to what its description actually lists;
   restricting `create_game`'s `owner_id`, `update_game`, `destroy_game`,
   `update_player`, or `update_action` to particular actors is real,
   defensible follow-up work, but it is not asked for here and doing it would
   both invent requirements and collide with other beads' designs (qss.14
   owns game-settings updates; the reactors that will eventually drive
   `update_player`/`update_action` are qss.5-8's territory).
6. **Superseded 2026-09-13, by owner decision: the dead see everything in
   their own game, and that now covers `Action` reads (and `Player.role`)
   too — see rules 5 and 8.** The previous reading held that chat's own
   "dead read everything" rule (qss.12) was chat-specific and did not extend
   to `:kill`/`:investigate` visibility, so a dead non-wolf still could not
   read a `:kill` row and a dead non-seer still could not read another
   seer's `:investigate` row. The owner's broader "a dead player is a
   spectator in an afterlife" decision replaces that reading outright: it is
   not scoped to chat, and this spec no longer treats chat's rule and this
   one as separate. `:kill` remains visible to any *living* werewolf seat
   regardless of the row's own actor (point 3, unaffected); what changes is
   that a *dead* seat of any role now also sees it, and every other
   restricted row type besides.
7. **The two "From 27w.1 review" `Accounts` notes are folded in as rules 13-17**,
   even though `User` is not a "Games resource," because the bead's NOTES
   assign them here explicitly. One of the four sub-items — deciding whether
   an unconfirmed user may act in games — is resolved as moot: `User` has no
   `confirmed_at` attribute; 27w.7 already made magic-link redemption itself
   the only account-creation path, so there is no unconfirmed state left to
   gate (rule 16, withdrawn).
8. **Binding `Game.owner_id` (on `create_game`) to the calling actor is out of
   scope.** It is the same shape of hole as `send_message`'s `author_id` and
   `Action`'s `actor_id`, and arguably "actions only as yourself" could be
   read to cover it too — but every existing `create_game` test (and qss.3's
   own design) sets `owner_id` to an arbitrary generated user with no actor
   in play at all, and 27w.3 (which actually wires a public `createGame`
   mutation) is the bead positioned to derive `owner_id` from the mutation's
   caller. Flagging this as a related gap this bead does not close.
9. **27w.2 now formally depends on 27w.9** (display names), whose NOTES on
   this bead require a narrow `User` read grant (rule 17) so a fellow player
   can read another player's name through `Player.user`/
   `Message.author.user`. Because that dependency exists, whoever codes this
   bead always starts from a `main` that already has `User.name` — rule 17
   grants `:id` and `:name` unconditionally, with no fallback case to write
   for a `:name` that doesn't exist yet.
10. **This spec is current against `main` `034a775`.** Since the last
    revision, qss.4 (Action validations, the `:kill` action, one action per
    phase; PR #5), 27w.9 (display names; PR #6) and 27w.8 (real magic-link
    email; PR #7) have all merged. qss.4's shape was already folded into the
    rules below (rule 7's `:kill`/`create_kill_action`, rule 8's `:kill` read
    narrowing, the `:vote`/`:investigate`/`:protect`/`:shoot` naming
    throughout). 27w.9 and 27w.8 needed no rule changes beyond rule 13/17
    reconciliation (see rule 13) — every breakage entry below is re-verified
    against this commit, with the grep evidence to show it.
11. **This revision is current against `main` `e6e6158`.** Since assumption
    10's commit, three more beads merged: qss.18 (action target validity —
    `Action.Validations.ActorAndTargetInGame`/`NoConsecutiveProtect`/
    `TargetAlive`, PR merge `ad2c0ac`), qss.14 (owner-configurable game setup
    — `Game`'s `:update_settings` action, `RoleAssignment.composition/2`,
    `Player.Validations.GameNotFull`, PR merge `eba2f09`) and qss.5 (EndDay
    reactor: lynch resolution — `Game.Changes.ResolveDayVote`,
    `Reactors.ResolveLynch`, PR merge `99a4615`). Every rule, Acceptance item
    and breakage entry below has been re-verified against this commit, by
    grep or by reading the file, not carried over from the previous
    revision unchecked. Three corrections of substance came out of that
    re-verification, each documented at its own rule/entry below rather than
    here: `:update_settings` now gets the same owner-only policy as `:start`
    (rule 3b, decision 7 above); rule 4's `deal_roles.ex` forced-consequence
    paragraph is rewritten because qss.14 replaced the guarded
    `composition/1` it described with an unguarded `composition/2` (the
    actual failure mode of an unfixed read is traced fresh, not assumed —
    see rule 4); and rule 8's `resolve_lynch.ex` paragraph is rewritten from
    a conditional ("if this file exists") to a statement of fact, since
    qss.5 merged the file with the fix already in place (see rule 8).
12. **This revision responds to a spec review that found two blockers, both
    verified against the running code, not just read.** First: rule 3
    (now split into 3a/3b) originally claimed the policy on `:start`/
    `:update_settings` ran before `ActorIsOwner`'s validation and changed
    the non-owner/anonymous failure class to `Forbidden`; it does not,
    because Ash checks a changeset's build-time validations before
    authorization — confirmed by running a scratch resource shaped the same
    way, not by reading the source (see decision 8 and rules 3a/3b, which
    also add the production fix this implies: `before_action?: true` on
    both `ActorIsOwner` validations). Second: `join_game` was claimed
    unaffected by rule 6 (staying open); it silently breaks instead, because
    `Player.Changes.ResolveGameByJoinCode`'s own `Games.get_game_by_join_code/1`
    call (`lib/werewolf_ash/games/player/changes/resolve_game_by_join_code.ex:20`)
    passes no options at all, so it runs with `actor: nil` under rule 1's
    new `Game` read policy and never finds the game a not-yet-seated joiner
    is trying to join — confirmed both by grep (this was the one call this
    spec's own "every Games.get/list call missing `authorize?`" audit
    missed, because it is missing every option, not just `authorize?`) and
    by running an equivalent scratch resource (see rule 4's new paragraph
    and rule 6).

## Goal

Every Games resource (`Game`, `Player`, `Action`, `Message`) carries real Ash
policies instead of being wide open to any caller that reaches the domain:
players can only read games and rosters they belong to, only their own role
(or a fellow werewolf's), only wolf-vote and their-own-investigate action
detail under the extra rules the game requires, only the owner can start a
game or change its settings, and every write that identifies "who did this" (`send_message`,
`Action` creation) is bound to the caller's own seat rather than trusting a
supplied id. `WerewolfAsh.Accounts.User` gets the same treatment tidied up
per its own review follow-ups: an explicit, tested deny for anything outside
its existing sign-in/current-user surface, a token-revocation test, and a
`current_user` preparation that no longer leans on a private Ash function.

## Rules

1. `Game` gains `authorizers: [Ash.Policy.Authorizer]`. Its `:read` action
   (and therefore `get_game`, `list_games`, `get_game_by_join_code`) is
   restricted: an actor may read a `Game` only while they hold a `Player` seat
   in it — any role, alive or dead. An actor with no seat, or no actor at all,
   gets nothing back (an empty list, or a not-found result for a `get`-style
   call) — never a hard authorization error, since read policies filter by
   default.
2. `Game`'s `:create`, `:update`, `:destroy`, `:finish`, `:end_day` and
   `:end_night` actions stay exactly as open as they are today
   (`authorize_if always()`), added explicitly so adding the authorizer does
   not silently default-deny them. `:end_day`/`:end_night` in particular are
   never called by a request actor — only by the not-yet-built scheduler —
   so they get no actor-based restriction here or anywhere else in this bead.
3a. `Game`'s `:start` action gains a policy —
   `authorize_if relates_to_actor_via(:owner)` or an equivalent expression —
   layered on top of qss.3's `Game.Validations.ActorIsOwner` validation. A
   non-owner or anonymous actor is now forbidden by the policy; an owner
   actor sees the same `start` behavior as before this bead.

   **Production change, by owner decision (decision 8 above): `start`'s
   `validate ActorIsOwner` becomes `validate ActorIsOwner, before_action?:
   true`.** Without this, the policy is unreachable — confirmed by running
   a scratch resource shaped exactly like `Game`'s `:start` (a policy plus
   an ordinary, build-time `ActorIsOwner`-style validation): both a
   stranger actor and a nil actor got the validation's own
   `Ash.Error.Invalid{errors: [%Ash.Error.Changes.InvalidAttribute{field:
   :owner_id}]}`, never the policy's error, because Ash resolves a
   changeset's build-time validations before authorization runs
   (`deps/ash/lib/ash/actions/update/update.ex:19`'s first clause returns
   an invalid changeset's errors before the authorization step at `:339`).
   `owner_id` being already present on the loaded `Game` struct does let
   the policy resolve statically, but that was never the reason the
   validation ran second — deleting the policy entirely, with the
   validation still build-time, would not fail a single test. Moving the
   validation to `before_action?: true` defers it to run *after*
   authorization instead (confirmed by re-running the same scratch
   resource with only that option added: stranger and nil actor both now
   get `Ash.Error.Forbidden{errors: [%Ash.Error.Forbidden.Policy{}]}`, the
   owner still succeeds, and a stranger actor called with `authorize?:
   false` — bypassing the policy entirely — still gets the validation's own
   `Ash.Error.Invalid`, the backstop decision 8 describes). `start` is
   already `require_atomic? false` (`lib/werewolf_ash/games/game.ex:109`),
   which a `before_action?: true` validation requires (it cannot run
   atomically) — no change needed there.

   `start`'s other validations, `MinimumPlayers` and `RoleCompositionFits`,
   are **not** moved to `before_action?: true` and stay exactly as they
   are: ordinary, build-time validations that still run before
   authorization, same as always. So the precise contract is: a non-owner
   or anonymous actor calling `start` on an otherwise-valid request (a
   well-formed, >= 5-player lobby whose composition fits) is forbidden with
   `Ash.Error.Forbidden{errors: [%Ash.Error.Forbidden.Policy{}]}`; a
   request that would *also* fail `MinimumPlayers`/`RoleCompositionFits`
   still gets that validation's ordinary `Ash.Error.Invalid`, regardless of
   who is calling, because those validations run first and are unaffected
   by who the actor is. This is a real, intentional change to `start`'s
   owner/anonymous negative-case contract for an otherwise-valid request —
   see the fix to games_test.exs's "requires the owner as actor..." test
   below, which is already set up with a well-formed >= 5-player lobby and
   needs no setup change, only its assertion corrected.
3b. **Extended 2026-09-13, by owner decision (decisions 7 and 8 above), now
   that qss.14 has merged and landed first:** `Game`'s `:update_settings`
   action (qss.14's own action, code interface `update_game_settings`)
   gains the identical policy and the identical production change, for the
   identical reason, layered on qss.14's own `ActorIsOwner` validation on
   that same action (`lib/werewolf_ash/games/game.ex`, the
   `:update_settings` action block): `validate ActorIsOwner` becomes
   `validate ActorIsOwner, before_action?: true`. `update_settings` is
   already `require_atomic? false` (`lib/werewolf_ash/games/game.ex:83`).
   A non-owner or anonymous actor is forbidden with
   `Ash.Error.Forbidden{errors: [%Ash.Error.Forbidden.Policy{}]}`; an owner
   actor sees `:update_settings` behave exactly as qss.14 shipped it.

   `:update_settings`'s other validations — `attribute_equals(:state,
   :lobby)`, `PositivePlayerBounds`, `MinNotAboveMax`,
   `ManualWerewolfCountValid`, `CompositionFitsAtCap` and
   `MaxPlayersNotBelowSeated` (the last already `before_action?: true` in
   its own right, for its own, unrelated locking reason — see its
   moduledoc) — are **not** touched by this rule and stay exactly as qss.14
   shipped them: every one but `MaxPlayersNotBelowSeated` is an ordinary,
   build-time validation that still runs before authorization. So, exactly
   as rule 3a: a non-owner or anonymous actor calling `update_settings` on
   an otherwise-valid request (the game still `:lobby`, the settings
   themselves internally consistent, seated count under any new
   `max_players`) is forbidden with `Ash.Error.Forbidden`; a request that
   would *also* fail `attribute_equals(:state, :lobby)`,
   `PositivePlayerBounds`, `MinNotAboveMax`, `ManualWerewolfCountValid` or
   `CompositionFitsAtCap` still gets that validation's ordinary
   `Ash.Error.Invalid` first, regardless of who is calling, since those five
   stay build-time and unaffected by this rule. `MaxPlayersNotBelowSeated`
   is the one exception worth naming, not because this rule touches it, but
   because it was already `before_action?: true` before this bead: a
   request that would also fail it now gets `Ash.Error.Forbidden` first for
   a non-owner. Authorization (`Ash.Actions.Update.do_run/4`'s `authorize/2`
   step, `deps/ash/lib/ash/actions/update/update.ex:339`) runs as its own
   pipeline stage strictly before `commit/3`, and every `before_action?`
   hook — `ActorIsOwner`'s new one and `MaxPlayersNotBelowSeated`'s
   existing one alike — runs inside `commit/3`, so the policy always
   decides before either before_action? validation gets a chance to,
   regardless of their relative order. The existing tests pinning
   `MaxPlayersNotBelowSeated`'s own behavior (`game_not_full_test.exs`,
   `max_players_not_below_seated_test.exs`) call it directly on a bare
   changeset with no actor/policy in play at all, so this ordering
   question does not reach them; no new test is needed to pin it either,
   since nothing in this bead's Acceptance claims a specific ordering
   between the two before_action? validations, only that the policy
   precedes both, which rule 3a's own pin already covers generically. This
   is the one
   policy `Game` needs beyond `:start`'s: every other Game action qss.14
   added or touched (the validations themselves,
   `RoleAssignment.composition/2`) is a game rule about what settings are
   *valid*, not about who may change them, and stays out of this bead's
   scope (see Out of scope). See games_test.exs's "update_game_settings"
   describe block, "rejects a caller other than the game's own owner (rule
   2)" test, below (already set up with a game still in `:lobby`, no setup
   change needed, only its assertion corrected), for the one existing test
   this fixes, and the Acceptance section for the new "no actor at all"
   case that test does not yet cover.
4. `Player` gains `authorizers: [Ash.Policy.Authorizer]`. It gets a single
   `policy action_type(:read)`, restricted the same way as `Game`'s: an
   actor may read a `Player` row only while they themselves hold a seat —
   any role, alive or dead — in that row's game. This is the bead's own
   words ("players read games they belong to") applied to `Player`, and
   `action_type(:read)` deliberately covers *both* of `Player`'s read
   actions — the bare `:read` default and `:living_in_game` — not just the
   one named `:read`.

   A forced consequence of gating `:living_in_game`: `CheckWin`'s
   `read :living_players, Player, :living_in_game` reactor step
   (`lib/werewolf_ash/games/reactors/check_win.ex`) runs with no actor. Once
   this rule exists, that step needs `authorize?: false` (a documented,
   valid option on Ash.Reactor's `read` DSL entity) or it silently returns
   zero living players for every game, not just in tests — this is not a
   free-standing production change, it is this rule reaching a real caller.

   A second, identical forced consequence, this time of gating the bare
   `:read` action: `Game.Changes.DealRoles.deal/2`
   (`lib/werewolf_ash/games/game/changes/deal_roles.ex:28`) calls
   `Games.list_players!(query: [filter: [game_id: game.id]])` with no
   `opts` at all — unlike its own sibling call two lines later (`:34`,
   `Games.update_player(player, %{role: role}, opts)`), which already
   forwards the `opts` `deal/2` was given and must stay exactly as it is.
   Once this rule exists, line 28 needs `authorize?: false` added directly
   (not `opts` forwarded) — this is a game rule fetching the roster it is
   about to deal from, not an access check, the same reasoning
   `AuthorMayPost.load_author/1` already uses, and it matches
   `Game.Validations.MinimumPlayers`'s identical `authorize?: false` on the
   same query one file over (`minimum_players.ex:16`). Forwarding `opts`
   instead would be the wrong fix here: `deal/2` must find every seated
   player regardless of whether the actor who called `start` happens to
   still be one of them.

   **Rewritten 2026-09-13: the failure mode of leaving line 28 unfixed has
   changed since the last revision, and the old wording ("`start` deals zero
   players silently") is no longer accurate — verify this for yourself
   rather than trust either description.** qss.14 replaced
   `RoleAssignment.composition/1`, which this paragraph used to cite for its
   `when player_count >= 5` guard, with `composition/2`
   (`lib/werewolf_ash/games/game/role_assignment.ex:23`), whose only guard
   is `when is_integer(player_count)` — no minimum at all, by design: its
   own moduledoc says composition is "only ever called once `start` has
   already confirmed the composition fits the actual seated count," so it
   "enforces no minimum of its own." Left unfixed, line 28's policy-filtered
   read (`actor: nil`) returns `[]` regardless of the real roster size, so
   `deal/2` calls `composition(0, game)`. Traced against the actual
   attribute defaults every existing pin test uses (`seer_enabled`,
   `bodyguard_enabled` and `hunter_enabled` all default `true`,
   `role_distribution_mode` defaults `:automatic`): `specials(settings)`
   returns 3 roles, `werewolf_count(0, settings)` is
   `max(1, div(0, 4)) == 1`, so `villagers = 0 - 3 - 1 == -4`, and
   `List.duplicate(:villager, -4)` — not `Enum.zip/2` — is what actually
   raises, with `FunctionClauseError` (List.duplicate/2 requires a
   non-negative count), still inside `deal/2`'s own `after_action` hook,
   still before any zipping happens. This was confirmed by direct
   execution against this commit (`RoleAssignment.composition(0, %{
   role_distribution_mode: :automatic, manual_werewolf_count: nil,
   seer_enabled: true, bodyguard_enabled: true, hunter_enabled: true})`
   raises `FunctionClauseError, "no function clause matching in
   List.duplicate/2"`), not assumed from the diff. So for every settings
   configuration currently exercised by any pin test — every one of them
   uses `game()`'s defaults, none override the specials or switch to manual
   mode with zero wolves — an unfixed line 28 still fails loudly, exactly
   as it did before qss.14, just from a different function for a different
   reason: a coder who fixes the field-policy break in a pin test's own
   `list_players!`/`get_player!` call (rule 5, below) but skips line 28
   still gets an immediate crash. **Do not "fix" that crash by adding a
   guard back to `composition/2`** — qss.14 removed it deliberately, so that
   a game with `min_players` set below 5 (qss.14's own feature) can still
   deal roles to a legitimately small roster; a coder confirms this against
   `role_composition_fits_test.exs`'s own "a below-4 seat count with every
   special disabled passes (rule 8's guard removal)" test before touching
   that guard at all. The empty roster is still the bug, not the guard's
   absence.

   A genuinely *silent* failure — `composition/2` returning `[]` and
   `deal/2` completing having dealt nothing, no crash at all — is possible
   only in a settings configuration no pin test currently uses: every
   special disabled *and* manual mode with `manual_werewolf_count: 0`
   (confirmed the same way: `composition(0, %{role_distribution_mode:
   :manual, manual_werewolf_count: 0, seer_enabled: false,
   bodyguard_enabled: false, hunter_enabled: false}) == []`). The fix is
   identical either way — `authorize?: false` on line 28 — but a coder must
   not treat "the existing tests still crash if I skip this" as proof the
   fix is optional or as a substitute for actually making it: a differently
   configured game (or a future test using one) hits the silent path, not
   the crash, and ships with zero roles dealt.

   **A third forced consequence, added this revision after the spec review
   found it: gating `Game`'s `:read` action (rule 1) also breaks joining a
   game, and this spec previously said rule 6 left `:join` unaffected —
   that was wrong.** `Player.Changes.ResolveGameByJoinCode.change/3`
   (`lib/werewolf_ash/games/player/changes/resolve_game_by_join_code.ex:17-20`)
   ignores its own `_context` entirely and calls `Games.get_game_by_join_code(join_code)`
   with no options at all — not even a forwarded `opts`, unlike every other
   internal read this spec already audited. Once rule 1 exists, this read
   runs with `actor: nil` under the domain's `authorize: :by_default`
   default, and a user who is not yet seated in the game they are trying to
   join — which, by definition, is *every* caller of `:join`, seated or not
   — can never pass rule 1's "holds a seat in it" condition for a game they
   don't hold a seat in yet. The lookup returns `{:error, _}` unconditionally,
   `ResolveGameByJoinCode` reports "does not match any game" on `:join_code`,
   and `join_game`/`join_game!` fail for every join code, valid or not, in
   production, not just in tests. Confirmed by running an equivalent scratch
   resource (a `Game`-shaped ETS resource with a seat-gated `:read` policy
   and a `get_by`-style lookup called with no options): the lookup returned
   `Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}` before the
   fix and `{:ok, record}` after adding `authorize?: false`. This is the
   same "game rule, not an access check" reasoning as `deal_roles.ex:28`
   and `CheckWin`'s read above: resolving a join code to the `Game` it
   names is not itself a read the *joining* actor needs to already be
   authorized for — `Player`'s own `:join` policy (rule 6, unchanged, still
   open) is what actually decides whether the seat gets created. The fix is
   `authorize?: false` added directly to this one call; the public
   `get_game_by_join_code` code interface itself (rule 1's own grant) is
   unaffected and stays seat-gated — this is a different, internal call
   inside a different action's own change, not the same read qss.3's
   `get_game_by_join_code/1,2` exposes.

   Every `Games.get_*`/`Games.list_*` and `Ash.get`/`Ash.read`/`Ash.load`
   call across all of `lib/` was re-grepped this revision, specifically to
   catch this shape (a call with *no* options at all, not just a missing
   `authorize?:` — the previous revision's audit only looked for the
   latter):

   ```
   $ grep -rnE 'Games\.(get|list)_[a-z_]*!?\(' lib/ --include='*.ex'
   lib/werewolf_ash/games/reactors/resolve_lynch.ex:57:        Games.list_actions!(
   lib/werewolf_ash/games/reactors/resolve_lynch.ex:85:    run fn %{game_id: game_id}, _context -> Games.get_game(game_id, authorize?: false) end
   lib/werewolf_ash/games/reactors/resolve_lynch.ex:135:    with {:ok, target} <- Games.get_player(target_id, authorize?: false) do
   lib/werewolf_ash/games/game/changes/deal_roles.ex:28:    players = Games.list_players!(query: [filter: [game_id: game.id]])
   lib/werewolf_ash/games/game/validations/max_players_not_below_seated.ex:14:  `Games.get_game(game_id, authorize?: false, lock: :for_update)`, the same
   lib/werewolf_ash/games/game/validations/max_players_not_below_seated.ex:38:    case Games.get_game(game_id, authorize?: false, lock: :for_update) do
   lib/werewolf_ash/games/game/validations/max_players_not_below_seated.ex:41:          Games.list_players!(query: [filter: [game_id: game.id]], authorize?: false)
   lib/werewolf_ash/games/game/validations/role_composition_fits.ex:18:      Games.list_players!(query: [filter: [game_id: game.id]], authorize?: false)
   lib/werewolf_ash/games/game/validations/minimum_players.ex:16:      Games.list_players!(query: [filter: [game_id: changeset.data.id]], authorize?: false)
   lib/werewolf_ash/games/action/changes/apply_kill.ex:36:      with {:ok, target} <- Games.get_player(action.target_id, opts),
   lib/werewolf_ash/games/action/changes/apply_kill.ex:44:    with {:ok, phase} <- Games.get_phase(action.phase_id, opts),
   lib/werewolf_ash/games/action/changes/apply_kill.ex:47:        Games.list_actions!(
   lib/werewolf_ash/games/action/changes/apply_kill.ex:64:    case Games.list_phases!(
   lib/werewolf_ash/games/action/changes/record_investigation_result.ex:37:    case Games.get_player(target_id, authorize?: false) do
   lib/werewolf_ash/games/action/validations/shoot_requires_pending_hunter.ex:40:           Games.get_player(actor_id, authorize?: false),
   lib/werewolf_ash/games/action/validations/shoot_requires_pending_hunter.ex:41:         {:ok, %{state: :hunter_pending}} <- Games.get_game(game_id, authorize?: false) do
   lib/werewolf_ash/games/action/validations/no_consecutive_protect.ex:38:    with {:ok, phase} <- Games.get_phase(phase_id, authorize?: false),
   lib/werewolf_ash/games/action/validations/no_consecutive_protect.ex:49:    case Games.list_phases!(
   lib/werewolf_ash/games/action/validations/no_consecutive_protect.ex:63:    case Games.list_actions!(
   lib/werewolf_ash/games/action/validations/actor_alive.ex:26:        case Games.get_player(actor_id, authorize?: false) do
   lib/werewolf_ash/games/action/validations/actor_and_target_in_game.ex:31:        case Games.get_phase(phase_id, authorize?: false) do
   lib/werewolf_ash/games/action/validations/actor_and_target_in_game.ex:53:        case Games.get_player(player_id, authorize?: false) do
   lib/werewolf_ash/games/action/validations/type_requires_phase_and_role.ex:49:        case Games.get_phase(phase_id, authorize?: false) do
   lib/werewolf_ash/games/action/validations/type_requires_phase_and_role.ex:67:        case Games.get_player(actor_id, authorize?: false) do
   lib/werewolf_ash/games/action/validations/target_alive.ex:26:        case Games.get_player(target_id, authorize?: false) do
   lib/werewolf_ash/games/player/changes/resolve_game_by_join_code.ex:20:    case Games.get_game_by_join_code(join_code) do
   lib/werewolf_ash/games/player/validations/game_not_full.ex:11:  `Games.get_game(game_id, authorize?: false, lock: :for_update)` has locked
   lib/werewolf_ash/games/player/validations/game_not_full.ex:43:    case Games.get_game(game_id, authorize?: false, lock: :for_update) do
   lib/werewolf_ash/games/player/validations/game_not_full.ex:49:          Games.list_players!(query: [filter: [game_id: game_id]], authorize?: false)
   lib/werewolf_ash/games/player/validations/game_in_lobby.ex:34:        case Games.get_game(game_id, authorize?: false) do
   $ grep -rn "Ash\.\(get\|get!\|read\|read!\|load\|load!\)(" lib/ --include="*.ex"
   lib/werewolf_ash/games/message/validations/author_may_post.ex:36:    case Ash.get(Player, author_id, authorize?: false) do
   lib/werewolf_ash/games/game/changes/advance_phase.ex:61:      Ash.load!(game, [:current_phase, :last_phase_number], opts)
   lib/werewolf_ash/games/game/changes/resolve_day_vote.ex:34:    case Ash.load!(game, :current_phase, Context.to_opts(context)) do
   lib/werewolf_ash/games/game/changes/resolve_day_vote.ex:50:    with {:ok, %{current_phase: phase}} <- Ash.load(game, [:current_phase], opts) do
   lib/werewolf_ash/games/player/validations/user_has_name.ex:28:        case Ash.get(User, user_id, authorize?: false) do
   ```

   Every hit but `resolve_game_by_join_code.ex:20` already carries
   `authorize?: false` explicitly, or forwards `opts`/`context` from a
   changeset built with them (`apply_kill.ex`'s two `Games.get_player`/
   `Games.get_phase` calls, already covered under rule 8 — forwarding is
   correct there, since a `Phase` load carries no policy either way and the
   `Player` load is the kill's own attributed effect, not an access check;
   `advance_phase.ex`/`resolve_day_vote.ex`'s `Ash.load` calls, which only
   ever load `Phase` relationships, unaffected by any policy this spec
   adds regardless of what `opts` they carry). `resolve_game_by_join_code.ex:20`
   is the one genuine gap this shape of grep catches that the previous
   revision's audit missed.

   The `Games.list_*!` hits are accounted for elsewhere in this spec:
   `deal_roles.ex:28` passes `query:` only and is rule 4's `DealRoles` fix;
   `resolve_lynch.ex:57` and `no_consecutive_protect.ex:49`/`:63` are
   multi-line calls whose `authorize?: false` sits on a following line;
   `apply_kill.ex:47`/`:64` forward `opts` and are covered by rule 8's
   `protected?/2` fix; `role_composition_fits.ex:18`, `minimum_players.ex:16`,
   `max_players_not_below_seated.ex:41` and `game_not_full.ex:49` carry
   `authorize?: false` on the line itself; `max_players_not_below_seated.ex:14`
   and `game_not_full.ex:11` are moduledoc text.
5. `Player` gains a field policy on `:role`: visible when the row is the
   reading actor's own seat, or when the reading actor holds a `:werewolf`
   seat in the same game *and* the row's own role is also `:werewolf`
   ("fellow wolves"), or **(added 2026-09-13, by owner decision)** when the
   row's own game has reached `:finished` — at that point every seat's role
   is visible to every other seat in the same game, living or dead, no
   condition on the reader at all — or **(added 2026-09-13, by owner
   decision)** when the reading actor's own seat in that same game is dead:
   "the dead see everything," a dead player is a spectator in an afterlife
   for the rest of that one game, so every other seat's role is visible to
   them regardless of team, once their own seat has died. (They still cannot
   *act* or post — this field policy only governs reads; rules 2/6/7's open
   write policies and `AuthorMayPost`'s own validation are unchanged, and
   nothing about death gates `:create` anywhere in this bead.) Hidden in
   every other case. Ash's
   field-policy rule that "if any field policy exists, every field needs
   one" means `Player` also needs a catch-all for its other fields (`id`,
   `game_id`, `user_id`, `alive`, `joined_at`) left open to anyone who
   already passes rule 4's resource-level read policy — this field policy
   narrows `:role` alone. A hidden role comes back as Ash's
   `%Ash.ForbiddenField{}` sentinel, not `nil` — tests must tell that apart
   from a real not-yet-dealt `role: nil`.

   The `:finished` condition is an `expr` crossing the `game` relationship
   (`expr(game.state == :finished)`, alongside the existing own-seat/
   fellow-wolf `authorize_if`s in the same `field_policy :role` block, all
   OR'd together per Ash's normal multiple-checks-in-one-policy semantics).
   This is not a novel shape: the DSL already supports a field policy
   `authorize_if expr(...)` reading a field through a `belongs_to`
   relationship, one hop, exactly like `Player`'s own `belongs_to :game`
   here (`deps/ash/documentation/topics/security/policies.md:946-950`'s
   `field_policy :email, always() do authorize_if expr(user.id ==
   ^actor(:id)) end` example, crossing a `user` relationship the same way).
   The relationship crossed by a field-policy `expr` is not itself
   re-authorized through `Game`'s own read policy (rule 1) — the field
   policy's check compiles to a loaded `Ash.Resource.Calculation.Expression`
   (`deps/ash/lib/ash/policy/authorizer/authorizer.ex:1558,1640-1649`), and per
   `deps/ash/documentation/topics/security/policies.md:889-895`'s
   "Calculations" section, "the dependencies of a calculation do not have
   any authorization applied to them" — so a reading `Player`'s own `game`
   relationship resolves for this check regardless of whether that actor
   could independently pass `Game`'s `:read` policy on that row. (In
   practice they always could, per rule 4/1's shared baseline, but the field
   policy does not depend on it either way.)

   The "dead sees everything" condition is a second, independent `expr` in
   the same `field_policy :role` block:
   `expr(exists(game.players, user_id == ^actor(:id) and not alive))` —
   "does the reading actor hold *some* seat, any seat, in this row's game,
   and is that seat's own `alive` false." This is not a new relationship
   shape either: `WerewolfAsh.Games.Message.Visibility.visible_to/1`
   (`lib/werewolf_ash/games/message/visibility.ex:32-34`) already builds
   exactly this — `expr(exists(game.players, ^player_match and
   ^player_may_read()))` — and `player_may_read/0`
   (`lib/werewolf_ash/games/message/visibility.ex:21-23`) already writes
   `not alive` in an expr the same way. What's new here is only that this
   `exists` sits inside a *field* policy rather than a *row* policy, i.e.
   whether the field-policy compiler (rule 5's `:finished` paragraph above)
   accepts an `exists`-shaped expression at all, not just a plain
   dotted-path one. It does: `Ash.Resource.Calculation.Expression.load/3`
   (`deps/ash/lib/ash/resource/calculation/expression.ex:103-140`) walks the
   compiled expression with `Ash.Filter.list_refs/1`, which has its own
   clause for a related `%Ash.Query.Exists{at_path: at_path, path: path,
   expr: expr}` (`deps/ash/lib/ash/filter/filter.ex:2825-2840`): it recurses
   into the exists's own inner `expr` and returns the plain attribute refs
   it finds there (`user_id`, `alive`) with their `relationship_path`
   prefixed by `at_path ++ path` — i.e. `["game", "players"]` — the same
   "plain attribute ref at a relationship path" shape `game.state` already
   uses in the `:finished` condition above, just one hop further out. There
   is no separate aggregate-loading step for `exists` itself: the path this
   returns is what gets loaded, `game.players` is then present on the
   record, and `exists(...)`'s own boolean is evaluated in memory over that
   loaded data when the calculation runs
   (`Ash.Resource.Calculation.Expression.calculate/3`, same module, via
   `Ash.Expr.eval_hydrated/2` and `Ash.Filter.Runtime`'s own `Exists`
   resolution). No separate check module is needed for either condition; a
   coder could reasonably move both into a
   `WerewolfAsh.Games.Player.Visibility` helper mirroring `Message.Visibility`'s
   shape, but nothing in this bead requires it.

   This absorbs the role-reveal half of qss.17's description
   ("`Game.state == :finished` reveals every role to every seat"), which the
   owner folded into this bead on 2026-09-13 (qss.17's own NOTES record it).
   It does not absorb qss.17's other two mentions: "alive status" needs no
   change (already unconditional under rule 4's baseline, before and after
   this bead); "the game-over event carries the winner" is qss.11's. See
   `werewolf_ash-qss.19`'s bead NOTES for a related gap this rule does not
   settle: qss.19's own dawn reveal of a dead player's role.
6. `Player`'s `:create`, `:join`, `:update` and `:destroy` actions stay
   exactly as open as they are today (`authorize_if always()`) — `:join` is
   named explicitly here, not left to fall through Assumption 5's general
   default, because leaving it unnamed means Ash's default-deny actually
   bites: `:join` is a real, callable action (qss.3's `join_game`) with
   nothing else in this bead's rules covering it. `add_player`/
   `create_game`'s `players` argument keep seating arbitrary users;
   `join_game`/`update_player`/`remove_player` keep their current callers
   working, including with no actor at all — `Player`'s own policy needs no
   test change for this rule, since staying open preserves today's `Player`
   behavior exactly.

   **Correction, this revision: this is not the same as "no existing
   `join_game` test needs any change."** Rule 6 leaving `Player`'s `:join`
   open says nothing about whether `join_game` keeps *working* once rule 1
   exists — it doesn't, without rule 4's new `resolve_game_by_join_code.ex`
   fix (above): every `join_game`/`join_game!` call in the suite, actored
   or not, fails once `Game` gains a read policy, until that one line gets
   `authorize?: false`. With that production fix in place, every existing
   `join_game`/`join_game!` call keeps working exactly as before, actor or
   no actor, which is what this rule's own "no change" claim actually
   means — see the games_test.exs entries below for the specific call
   sites this was checked against.
7. `Action` gains `authorizers: [Ash.Policy.Authorizer]`. Its `:create` action
   and qss.4's separate `:kill` action (code interface `create_kill_action`)
   each gain the same policy: the row's `actor_id` must reference a `Player` whose
   `user_id` equals the calling actor's id ("actions only as yourself", per
   Assumption 2) — anyone else's `actor_id`, or no actor at all, is
   forbidden. This is independent of, and does not replace, qss.4's merged
   role/phase/aliveness/once-per-phase validations.

   **Conditional extension, added 2026-09-13 per the qss.21 spec review:**
   qss.21 (changeable day votes/protections; unmerged as of this revision,
   and not a dependency of this bead in either direction) adds a *generic*
   `Action` action, `:withdraw` (code interface `withdraw_action/3`, taking
   `phase_id`, `actor_id` and `type` as arguments), which deletes or
   resolves the matching row rather than operating on one already loaded —
   it has no changeset and no row of its own to check `actor_id` against.
   If `Action` has a `:withdraw` action by the time this bead is
   implemented, it gets the same "only as yourself" policy as `:create`/
   `:kill` above, but written against the *argument*, not a row attribute:
   the `actor_id` argument must reference a `Player` whose `user_id` equals
   the calling actor's id; anyone else's `actor_id` argument, or no actor at
   all, is forbidden. Left unnamed, `:withdraw` falls to Assumption 5's
   `authorize_if always()` default and anyone could withdraw anyone else's
   vote or protection.

   A generic action's policy cannot reuse `:create`/`:kill`'s own check
   unchanged, because there is no changeset relationship to cross, and it
   cannot be a plain `expr()`/`Ash.Policy.FilterCheck` either, even one
   built from `arg(:actor_id)`: this must be a custom
   `Ash.Policy.SimpleCheck` that looks the `Player` up itself, the exact
   check qss.21's own spec rule 11 already specifies — read
   `docs/specs/werewolf_ash-qss.21.md` rule 11 before writing this so both
   specs describe the same check; this paragraph only restates it for a
   coder who reaches 27w.2 without qss.21 open.

   A `SimpleCheck`'s `match?/3` receives the actor and the full
   `Ash.Policy.Authorizer.t()` as its context — not a filterable
   query/changeset — per its own typespec, `@type context ::
   Ash.Policy.Authorizer.t()`
   (`deps/ash/lib/ash/policy/simple_check.ex:39`), and that struct carries
   the in-flight `action_input: Ash.ActionInput.t() | nil` field directly
   (`deps/ash/lib/ash/policy/authorizer/authorizer.ex:32`). The check reads
   `Ash.ActionInput.get_argument(action_input, :actor_id)`
   (`deps/ash/lib/ash/action_input.ex:516`), looks up that `Player` with
   `authorize?: false` (a game-rule identity check, not an access check —
   the same convention `Message.Validations.AuthorMayPost` and
   `Player.Validations.UserHasName` already use), and returns whether its
   `user_id` equals the actor's id — `{:ok, false}` (not raising) for a
   missing or mismatched `Player`, or no actor at all.

   A filter-style check (`expr()`, including one built from
   `^arg(:actor_id)` alone, or an `exists(Player, ...)` "unrelated exists")
   does not work here and must not be used: an `Ash.Policy.FilterCheck` on
   an `Ash.ActionInput` is evaluated in memory via
   `Ash.Expr.eval_hydrated/2`, filling `arg(...)` from
   `action_input.arguments` (`deps/ash/lib/ash/policy/filter_check.ex:154-186`
   `try_eval/2`'s `action_input` clause) — there is no query and no loaded
   record for it to run a data-layer `EXISTS` against. `exists`'s own
   in-memory evaluator returns `:unknown`, not `true`/`false`, whenever
   there is no record to resolve it against
   (`deps/ash/lib/ash/filter/runtime.ex:559-565`,
   `resolve_expr(%Ash.Query.Exists{}, nil, ...)`), and a generic action's
   authorization step raises outright the moment strict-checking any policy
   on it produces a filter (or a runtime "continue") instead of a plain
   `:authorized`/`:forbidden` decision — `"Cannot use filter checks with
   generic actions"` (`deps/ash/lib/ash/actions/action.ex:398-410`) or
   `"Cannot use runtime checks with generic actions"`
   (`deps/ash/lib/ash/actions/action.ex:412-417`). A `SimpleCheck` sidesteps
   this entirely because it never becomes a filter: `match?/3` runs its own
   database lookup and returns a plain boolean before strict-checking ever
   needs to reduce anything to a query.

   If `Action` has no `:withdraw` action at implementation time, this
   paragraph does not apply and nothing here needs building; per qss.21's
   own rule 11, if `:withdraw` is implemented before `Action` gains this
   bead's authorizer, qss.21's own coder adds this same check instead, using
   the identical mechanism.
8. `Action`'s `:read` action is restricted: an actor may read an `Action` row
   only while they hold a seat — any role, alive or dead — in that row's
   phase's game (the same baseline as rules 1 and 4), except:
   - a `:kill` row additionally requires the reading actor to hold a
     `:werewolf` seat in that game;
   - an `:investigate` row additionally requires the reading actor's own
     seat to be the row's `actor` (the seer who cast it);
   - **(revised 2026-09-13)** a `:protect` row additionally requires the
     reading actor's own seat to be the row's `actor` (the bodyguard who
     cast it) — the same shape as `:investigate`, and for the same reason:
     qss.21 makes protection changeable and withdrawable during the day, so
     a public `:protect` row would tell the wolves whom to avoid before
     night falls. Per Assumption 4 (revised), this narrows what was
     previously an unnarrowed baseline row.

   **(added 2026-09-13, by owner decision)** None of these three narrowings
   apply once the reading actor's own seat in that row's phase's game is
   dead: "the dead see everything" (the same decision as rule 5's fourth
   `:role` case) means a dead reader sees every `:kill`, `:investigate` and
   `:protect` row in that game, cast by or aimed at anyone, the same as a
   living reader already sees every `:vote`/`:shoot` row. The expression is
   the three-hop version of rule 5's own "dead" condition — `Action` has no
   direct `game` relationship, only `belongs_to :phase`
   (`lib/werewolf_ash/games/action.ex:111-114`), and `Phase` has
   `belongs_to :game` (`lib/werewolf_ash/games/phase.ex:69-72`), so the same
   `exists(_.players, user_id == ^actor(:id) and not alive)` shape becomes
   `expr(exists(phase.game.players, user_id == ^actor(:id) and not
   alive))`. This is not a deeper crossing than the baseline this same rule
   already needs: reaching `phase.game.players` at all is exactly the path
   rule 8's own opening sentence already requires ("hold a seat ... in that
   row's phase's game"), just without the `not alive` qualifier — a coder
   implementing the baseline and this exception writes the same relationship
   path twice, once with each condition.

   `:vote` and `:shoot` rows get no narrowing beyond the baseline, per
   Assumption 4 — a dead reader already sees them, the same as a living one.

   **Forced consequence of narrowing `:protect`:**
   `WerewolfAsh.Games.Action.Changes.ApplyKill.protected?/2`
   (`lib/werewolf_ash/games/action/changes/apply_kill.ex:43-59`) looks up the
   `:protect` row for the kill's target and preceding day phase from inside
   the `:kill` action's own `after_action` hook
   (`lib/werewolf_ash/games/action/changes/apply_kill.ex:26-29`), via
   `Games.list_actions!(Keyword.merge(opts, query: [filter: [phase_id:
   day_phase.id, type: :protect, target_id: action.target_id]]))` where
   `opts` is `Context.to_opts(context)` — the real `:kill` changeset's own
   context, i.e. the actor is the werewolf who submitted the kill, not the
   bodyguard. Once `:protect` is narrowed to the bodyguard who cast it, this
   call, run under the werewolf's own actor, would see no `:protect` row
   ever, whether or not one exists: `protects != []` (line 55) would always
   be `false`, so a protected target would die on every kill and the
   protection mechanism would silently stop working, in production, not
   just in tests. This is a game rule deciding whether a kill lands, not an
   access check by any of the actors involved — the same reasoning rule 4's
   `CheckWin` and `deal_roles.ex` reads already use. This one query, inside
   `protected?/2`, needs `authorize?: false` added directly, in place of the
   forwarded `opts` (the same "replace, don't forward" shape as
   `deal_roles.ex:28`'s own fix under rule 4). Its sibling calls in the same
   function are unaffected and keep forwarding `opts` unchanged: `Phase`
   carries no policy at all (Out of scope), so `Games.get_phase`/
   `Games.list_phases!`'s behavior does not depend on actor either way; and
   `Games.get_player`, `Games.update_player` and `Games.update_action` are
   the kill's own effect, correctly attributed to the werewolf who caused
   it, not a read this rule governs.

   **Settled 2026-09-13: qss.5 has merged, and the fix this paragraph used
   to describe conditionally is already in place — verified, not assumed.**
   qss.5 (day-vote resolution; merged as `99a4615`, not a dependency of this
   bead in either direction) added `lib/werewolf_ash/games/reactors/resolve_lynch.ex`,
   whose `:load_votes` step reads a day phase's `:vote` `Action` rows to
   tally the lynch:

   ```elixir
   Games.list_actions!(
     load: [:actor, :target],
     query: [filter: [phase_id: phase_id, type: :vote]],
     authorize?: false
   )
   ```

   (`lib/werewolf_ash/games/reactors/resolve_lynch.ex:55-61`). The base read
   already carries `authorize?: false`, so `:vote` — which gets no
   type-specific narrowing (above) but still sits behind rule 8's own
   opening baseline — is not filtered to `[]` the way an unauthenticated
   `Action` read elsewhere in this spec would be; this file needs no
   production change for rule 8.

   The same read also `load: [:actor, :target]` in one call, and those are
   `Player` reads (rule 4) — worth checking independently, since a load
   inside an otherwise-unauthorized read is not automatically unauthorized
   itself. It is, here: `authorize?: false` on a read sets
   `query.context.private.authorize?` via
   `Ash.Actions.Helpers.add_context/2`'s `private_context = Map.new(Keyword.take(opts,
   [:actor, :authorize?, :tracer]))` (`deps/ash/lib/ash/actions/helpers.ex:331-332`),
   and every relationship load `Ash.Actions.Read.Relationships` builds for
   it carries the identical value forward — **corrected this revision: the
   related query is a *new* `Ash.Query`, not the same struct reused**, but
   it is explicitly seeded with the parent query's own `authorize?`/`actor`.
   `related_query/4`'s non-lazy branch (the one actually exercised here,
   since `:actor`/`:target` are not already loaded on a freshly-read
   `Action`) pipes the fresh related query through
   `Ash.Actions.Read.for_read(read_action, nil, arguments, domain: domain,
   authorize?: query.context[:private][:authorize?], actor:
   query.context[:private][:actor], ...)`
   (`deps/ash/lib/ash/actions/read/relationships.ex:335`, `authorize?:`
   read off the *parent* query's context); the lazy-reuse branch a few
   lines above it does the identical thing at `:275`
   (`Ash.Query.for_read(read_action_name, arguments, domain: domain,
   authorize?: query.context[:private][:authorize?], ...)`). Either way,
   the new related query's own `authorize?`/`actor` are copied from the
   parent's, not inherited by sharing the same struct. So the `authorize?: false` on
   `:load_votes`'s own `Games.list_actions!` call already covers its
   `:actor`/`:target` loads too, by the same mechanism this spec's own rule
   5 paragraph relies on for a field policy's `expr` crossing a
   relationship (deps citations there, same file). No further fix is
   needed anywhere in `resolve_lynch.ex` for this bead's rules; the two
   other reads inside the same reactor (`:reload_game`'s
   `Games.get_game(game_id, authorize?: false)` and `apply_lynch/1`'s
   `Games.get_player/Games.update_player` calls, both already
   `authorize?: false`) were already correct for rules 1 and 4
   respectively, for the same "game rule, not an access check" reasoning
   this spec uses throughout.

   `resolve_day_vote_test.exs` and `resolve_lynch_test.exs` (qss.5's own
   test files) still need their *own* fixes below — not because
   `resolve_lynch.ex` itself is broken, but because both files call
   `Games.create_action!`/`Games.get_player!` directly, with no actor, to
   set up and verify the games they hand to the reactor, and those calls
   run through `Action`'s and `Player`'s own new policies exactly like any
   other actor-less test call in this spec. See "Existing tests this will
   break" below.
9. `Action`'s `:update` action (`update_action`, which records a result)
   stays exactly as open as it is today (`authorize_if always()`) — not
   named by this bead.
10. `Message` gains a read policy applying to every one of its read actions
    (its bare `:read` default and its `:visible_to` action alike):
    `authorize_if Visibility.visible_to(expr(user_id == ^actor(:id)))`,
    reusing `WerewolfAsh.Games.Message.Visibility` unchanged. This closes two
    holes flagged in qss.12's review: the bare `:read` action was completely
    unfiltered, and `:visible_to`'s caller-supplied `player_id` argument let
    a caller ask for any player's view — once this policy is in place the
    actor-based filter intersects with whatever the `player_id`-based filter
    returns, so a caller can never see more than their own actor identity
    permits regardless of which `player_id` they pass.
11. `Message`'s `:send_message` action gains a policy binding `author_id` to
    the caller: the row's `author_id` must reference a `Player` whose
    `user_id` equals the calling actor's id — anyone else's `author_id`, or
    no actor at all, is forbidden. Sending as someone else's player must
    fail with a policy/authorization-class error, distinguishable from
    `AuthorMayPost`'s own validation error (see rule 12) — this is the fix
    for the "author_id accepts anyone" hole qss.12's review flagged.
12. (withdrawn) Originally: reword `AuthorMayPost`'s wolves-channel rejection
    to a generic denial once rule 11 exists. Withdrawn on review: the only
    test that could pin this would assert on the message text, which the
    existing test standard (and this spec's own rule 12 sentence) forbids —
    a rule with no test that fails when it's deleted is not a rule. Rule 11
    already closes the substantive impersonation-oracle vector at the policy
    layer (the check resolves against `author_id`, an already-known input,
    before `AuthorMayPost`'s validation runs), which is the actual security
    property; a caller who still reaches `AuthorMayPost`'s validation is
    always posting as their own player and already knows their own role, so
    the wording was cosmetic. `AuthorMayPost`'s message is unchanged.

    Accounts follow-ups (from the 27w.1 review; `WerewolfAsh.Accounts.User`
    is not a Games resource, but the bead's NOTES bind these here):

13. Every `WerewolfAsh.Accounts.User` action other than `:request_magic_link`,
    `:sign_in_with_magic_link`, `:current_user`, `:set_name` (27w.9's own
    action, already policed with `authorize_if expr(id == ^actor(:id))` —
    "a user may only set their own display name," unaffected by anything in
    this bead), the AshAuthentication-internal interactions the existing
    `AshAuthenticationInteraction` bypass already covers (`:get_by_subject`,
    `:get_by_email`), and rule 17's narrow shared-game grant on `:read`, is
    forbidden for every actor, including no actor. Outside of rule 17's
    grant, this is already Ash's default-deny for
    an authorizer-bearing resource with no matching policy on a given
    action — no new production code is needed to pin it, just a policy test:
    the default-denied case is exercised by an actor who shares no game with
    the target calling `:read` (still nothing back, per rule 17's own
    condition), or, since rule 17 gives `:read` a real policy of its own,
    equally by any other `User` action this bead adds no policy for at all.
    Do not add a policy block that would also re-forbid the already-allowed
    actions: a trailing `policy always() do forbid_if
    always() end` applies to *every* action under Ash's
    all-matching-policies-must-pass rule and would break sign-in itself; if
    making the deny explicit in code is preferred over relying on the
    (already correct) default, convert the three existing allow-listed
    policies to `bypass` blocks first, the same shape already used for the
    `AshAuthenticationInteraction` policy.
14. After `AshAuthentication.TokenResource.revoke(WerewolfAsh.Accounts.Token,
    token)` revokes a signed-in user's bearer token, that token stops
    resolving: `WerewolfAsh.Accounts.BearerToken.user_from_token/1` returns
    `:error` for it, and a `currentUser` GraphQL query sent with that token
    as the bearer returns `null` — the same shape as an unrecognized token,
    not an error.
15. `WerewolfAsh.Accounts.User`'s `:current_user` action's `prepare` no
    longer calls the `@doc false` `Ash.Query.do_filter/2`. Either replace it
    with the public `Ash.Query.filter/2`, or drop the custom `prepare`
    entirely if the action's own `authorize_if expr(id == ^actor(:id))`
    policy already produces both existing behaviors on its own (an anonymous
    actor gets nothing without a `ReadActionRequiresActor` error; a
    mismatched actor gets nothing) — whichever is chosen, both behaviors must
    still hold and stay pinned by a test.
16. (withdrawn) Originally: "no change is made for unconfirmed users acting
    in games." Withdrawn on review: nothing fails if this is deleted, so it
    was never a rule — it's a resolved ambiguity, and stays recorded as
    Assumption 7 instead.
17. `WerewolfAsh.Accounts.User` gains a narrow additional *resource-level*
    read grant on `:read`, folded in here per this bead's NOTES from the
    27w.9 review: a signed-in actor may read a `User` row at all (not just
    their own, which `:current_user`'s existing policy already covers) when
    that `User` shares a seat in at least one game with the actor — i.e.
    there is a `Player` for each user pointing at the same `game_id`. This
    is what makes `Player.user`/`Message.author.user` resolve for a fellow
    player instead of only for yourself. `User` needs a
    `has_many :players, WerewolfAsh.Games.Player` relationship added to
    express "which games this user is seated in" — it has none today.

    It is not a grant to read the whole row once visible: `User` also gains
    a field policy restricting `:email`. `:id` and `:name` get the
    unconditional catch-all every other field needs once any field policy
    exists (`field_policy :* do authorize_if always() end`, the same shape
    as `Player`'s in rule 5) — **not** a second copy of the "shares a game"
    condition. This distinction matters: a signed-in user with no games yet
    reading their *own* `:name` via `currentUser` (`:current_user`'s
    resource policy already grants that row) must still see it — gating the
    `:id`/`:name` field policy on "shares a game" as well would wrongly hide
    a nameless-or-named user's own `name` from themselves before they have
    ever joined a game, breaking `auth_test.exs`'s `describe "setName /
    currentUser.name"` block (none of those four tests seat their user in
    any game). The "shares a game" condition belongs solely to the
    resource-level grant above, which decides whether a *row* is visible at
    all; it is not repeated at the field level.

    `:email`'s field policy cannot be simply `id == actor(:id)`: field
    policies are evaluated independently of resource-level `bypass`
    policies, and two of the request/sign-in flow's own reads of `email`
    have no actor at all. `Helpers.restrict_field_access/2`'s only skip
    condition is `internal?/1`, which checks `context.private.internal?`
    (`deps/ash/lib/ash/actions/helpers.ex:371-372`) — not
    `private.ash_authentication?`, so the existing `AshAuthenticationInteraction`
    resource-level bypass on `policies` does not exempt field-level
    evaluation, which runs through `Ash.Policy.Info.field_policies_for_field/2`
    on its own regardless. Two production paths read `email` with no actor
    and would otherwise raise or silently drop it:
    - `request_magic_link`, for an *already-registered* email
      (`deps/ash_authentication/lib/ash_authentication/strategies/magic_link/request.ex:56-66`):
      reads the `User` via `Ash.Query.for_read/3` with no actor, sets
      `context: %{private: %{ash_authentication?: true}}` on that query
      inline (lines 22-26) before running it, then calls `sender.send(user,
      token, ...)`.
      `WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmail.send/3`'s
      `%{email: email} -> to_string(email)` clause
      (`lib/werewolf_ash/accounts/user/senders/send_magic_link_email.ex:41`)
      then calls `to_string/1` on whatever `email` is — `%Ash.ForbiddenField{}`
      has no `String.Chars` implementation, so this raises.
      `authorize_if AshAuthentication.Checks.AshAuthenticationInteraction`
      (a `SimpleCheck`, valid in a field policy) fixes this: it matches on
      exactly the `private.ash_authentication?` context this read already
      sets.
    - `sign_in_with_magic_link` (`lib/werewolf_ash/accounts.ex`'s `create`
      mutation, calling the action directly): the create's own
      `AshAuthentication.Strategy.MagicLink.SignInChange` never sets
      `private.ash_authentication?` on the changeset — only
      `AshAuthentication.Strategy.MagicLink.Actions.sign_in/3`
      (`deps/ash_authentication/lib/ash_authentication/strategies/magic_link/actions.ex:64`)
      does that, and AshGraphql's `create` mutation does not call through
      that wrapper — it builds the changeset and calls `Ash.create/2`
      directly. So the `AshAuthenticationInteraction` check above does
      *not* cover this path; it needs its own
      `authorize_if action(:sign_in_with_magic_link)` (also a `SimpleCheck`,
      matching the current action by name, already used as a resource-level
      condition on `User` today) so the mutation's `result { email }` is not
      silently hidden.
    The full field policy is therefore three `authorize_if` checks, in any
    order (field policies OR their checks together): the two above, plus
    `expr(id == ^actor(:id))` for an ordinary self-read (`currentUser`).

## Out of scope

- Everything qss.3 owns: `join_game`'s/`leave`'s own business logic
  (`Player.Changes.ResolveGameByJoinCode`, `Player.Validations.GameInLobby`),
  role dealing (`Game.Changes.DealRoles`), the minimum-players check, and
  `Game.Validations.ActorIsOwner` itself, **except** the one-line
  `authorize?: false` fix to `ResolveGameByJoinCode`'s own
  `get_game_by_join_code` lookup (rule 4) that keeps `:join` working at
  all once rule 1 exists — a forced consequence of this bead's own read
  policy, not a change to qss.3's join logic itself (the lookup still
  resolves the identical game by the identical join code; only its
  authorization mode changes). This bead only adds that fix, the extra
  `:start`/`:update_settings` policy (rules 3a/3b) and the explicit open
  policy on `:join` (rule 6) on top of qss.3's work, and otherwise treats
  qss.3's Player/Game shape as a given (see Assumption 1).
- 27w.9's `:name` attribute itself, its own set-your-own-name mutation/
  policy, and its nameless-user-cannot-create/join-a-game validation. This
  bead only supplies the read grant (rule 17) that makes a name — once
  27w.9 adds one — visible to a fellow player; everything else about display
  names is 27w.9's (see Assumption 9).
- qss.4's `Action` validations (role, aliveness, phase, one action per
  phase). Rules 7-8 are purely about *who* may create/read an `Action` row,
  never about whether its contents make sense as a game move.
- qss.14's owner-configurable game settings are no longer entirely out of
  scope: rule 3b now adds the owner-only *gate* on `:update_settings` (see
  decisions 7-8). What stays out of scope is everything else qss.14 built —
  `PositivePlayerBounds`, `MinNotAboveMax`, `ManualWerewolfCountValid`,
  `CompositionFitsAtCap`, `MaxPlayersNotBelowSeated`,
  `RoleAssignment.composition/2`'s own formula, and `Player.Validations.GameNotFull` —
  none of which this bead touches; they decide what settings/rosters are
  *valid*, not who may change them. `update_game`/`destroy_game` stay open
  to any actor, left open per rule 2/Assumption 5, unchanged by decision 7:
  `update_game` (name/timezone/windows) and `destroy_game` were never part
  of qss.14's settings surface and decision 7 does not extend to them.
- qss.17's game-over role reveal is no longer out of scope: the owner folded
  it into this bead on 2026-09-13 (qss.17's own NOTES record the decision),
  and rule 5 now builds the `:finished` exception directly. What's still
  qss.17's own, not built here: qss.17's `Done:` line also asks for "the
  finished game's player list includes every role" as an end-to-end
  behavior and "the flip is driven by state, not by time" — both already
  fall out of rule 5's `expr(game.state == :finished)` condition with no
  extra work, so nothing is missing, but qss.17 should still close itself
  out against this bead rather than duplicate it. qss.17's description also
  says "the game-over event (qss.11) carries the winner" — that event is
  qss.11's, not this bead's, and nothing here changes because of it. See
  `werewolf_ash-qss.19`'s bead NOTES for a related gap this rule does not
  settle: qss.19's own dawn reveal of a dead player's role while a game is
  still in progress cannot rely on this bead's ordinary `Player.role` read
  policy, which stays closed until `:finished` (or the reader is dead
  themselves) — qss.19 needs its own mechanism for that reveal.
- GraphQL queries/mutations for any of this — that is 27w.3 (games) and
  27w.6 (chat), both of which depend on this bead.
- Binding `Game.create`'s `owner_id`, or `Player.create`'s/`join`'s
  `user_id`, to the calling actor — see Assumption 2 and 8.
- Any policy or field policy on `Phase`. Not named by the bead's description,
  and nothing here needs one (`AdvancePhase`'s internal phase
  creation/closing keeps working unauthorized either way).
- Narrowing `:vote`/`:shoot` `Action` visibility beyond the baseline —
  `:protect` is narrowed by rule 8 (revised 2026-09-13, Assumption 4);
  `:vote`/`:shoot` are not, and nothing about this revision changes that.
- Restricting `update_player` or `update_action` to particular callers — see
  Assumption 5.
- AshOban/scheduler wiring. `:end_day`/`:end_night` being system-only,
  actor-free calls is assumed here, not built.
- Any change to `Ash.Domain`'s `authorization` block on the `Games` or
  `Accounts` domain — the existing `authorize: :by_default` default is
  exactly what every rule above relies on; nothing needs overriding.

## Acceptance

- `WerewolfAsh.Games.get_game/1,2`, `WerewolfAsh.Games.list_games/0,1`,
  `WerewolfAsh.Games.get_game_by_join_code/1,2` — direct tests: a seated
  player (any role, dead or alive) can read their game; a user with no seat
  in it, and an anonymous actor, get nothing back, not an error.
- **Rule 3a**, `WerewolfAsh.Games.start_game/1,2,3` — direct tests, every
  one set up as an *otherwise-valid* request (a well-formed, >= 5-player
  lobby whose composition fits, exactly what `ready/0`'s existing fixture
  already builds): the owner actor starts the game exactly as before this
  bead; a non-owner actor and an anonymous actor are forbidden with
  `Ash.Error.Forbidden{errors: [%Ash.Error.Forbidden.Policy{}]}` (not
  qss.3's `ActorIsOwner`-validation `Ash.Error.Invalid`). Assert on error
  class/struct, not on message text. Two more tests pin the production fix
  itself, each engineered to fail for a different reason if the fix
  regresses: an otherwise-valid request from a non-owner still gets
  `Ash.Error.Forbidden` (this fails if `validate ActorIsOwner`'s
  `before_action?: true` is ever reverted to build-time, or if the policy
  is replaced by one that authorizes the non-owner, because the validation
  then returns `Ash.Error.Invalid` first; deleting the policy outright is
  caught by the owner-succeeds test instead whenever no other policy still
  applies to the action, because Ash then denies every actor by default,
  the owner included, so keep both tests); and
  a non-owner actor called with `authorize?: false` (bypassing the policy
  entirely) still gets `Ash.Error.Invalid{errors:
  [%Ash.Error.Changes.InvalidAttribute{field: :owner_id}]}` from the
  validation backstop, which fails if the validation is ever deleted
  instead of just reordered. A request that would *also* fail
  `MinimumPlayers`/`RoleCompositionFits` (fewer than 5 players, say) still
  gets that validation's own `Ash.Error.Invalid` regardless of actor —
  covered by the existing "requires at least 5 seated players" test, which
  needs no change (rules 3a's policy adds nothing to what that test
  already exercises with the owner as actor).
- **Rule 3b**, `WerewolfAsh.Games.update_game_settings/1,2,3` — direct
  tests, the identical shape as rule 3a's above, every one set up as an
  otherwise-valid request (the game still `:lobby`, the settings
  internally consistent): the owner actor changes settings exactly as
  qss.14 shipped it; a non-owner actor **and** an anonymous actor (the
  anonymous case is new — no existing test calls `update_game_settings`
  with no actor at all) are both forbidden with `Ash.Error.Forbidden{errors:
  [%Ash.Error.Forbidden.Policy{}]}` (not qss.14's own `ActorIsOwner`-validation
  `Ash.Error.Invalid`); the same two production-fix pins as rule 3a's (an
  otherwise-valid non-owner request stays `Forbidden` only while both the
  policy and the `before_action?: true` move are in place; a non-owner
  actor called with `authorize?: false` still gets the validation's
  `Ash.Error.Invalid` backstop). A request that would *also* fail
  `attribute_equals(:state, :lobby)` or one of qss.14's own settings
  validations still gets that validation's `Ash.Error.Invalid` regardless
  of actor — covered by the existing "rejects a change once the game has
  already left the lobby (rule 3)" test (qss.14's own rule numbering, not
  this spec's), which needs no change. Assert on error class/struct, not
  on message text. This replaces games_test.exs's existing "rejects a
  caller other than the game's own owner (rule 2)" test's stale assertion
  (see "Existing tests this will break" below) and adds the missing
  no-actor case next to it.
- `WerewolfAsh.Games.list_players/0,1`, `WerewolfAsh.Games.get_player/1,2`,
  `WerewolfAsh.Games.list_living_players/1` — direct tests: a fellow game
  member reads a `Player` row (living or dead, via any of the three); a
  user with no seat in that game cannot. `WerewolfAsh.Games.join_game/2,3`
  is **not** unaffected by this bead, despite rule 6 keeping `Player`'s
  `:join` policy open — rule 1's `Game` read policy breaks it, and rule 4's
  `resolve_game_by_join_code.ex` fix (`authorize?: false` on its internal
  `get_game_by_join_code` lookup) is what keeps it working; a direct test
  that a user with no prior seat can still join a lobby game by its
  join_code with no actor, exactly as qss.3 left it, is the pin for that
  fix — it fails (every join gets `:join_code` "does not match any game")
  without it.
- The `Player.role` field policy — direct tests (via `Ash.load!`/
  `Ash.read!` and asserting on the resulting value, or `Ash.can_see_fields?/3`):
  a player reads their own role; a werewolf reads a fellow werewolf's role; a
  villager reading a wolf's, the seer's, or another villager's role gets
  `%Ash.ForbiddenField{}`, not `nil`; in a game whose `state` is `:finished`,
  a villager reads a wolf's (or any other seat's) role; in the identical
  setup with the game still `:day`/`:night`/`:lobby`, the same read still
  comes back `%Ash.ForbiddenField{}` — the two tests must share every
  condition but the game's `state`, so the assertion actually pins the
  `:finished` check and not some other path to visibility (own seat, fellow
  wolf); a dead villager reads a living wolf's role in an ongoing (not
  `:finished`) game, paired with the same setup but the reading villager
  still alive, which must still come back `%Ash.ForbiddenField{}` — again
  sharing every condition but the reader's own `alive`, so the assertion
  pins the "dead sees everything" check specifically.
- `WerewolfAsh.Games.create_action/4,5,6` — direct tests: creating an
  `Action` with `actor_id` set to the caller's own player succeeds;
  set to any other player's id, or with no actor, is forbidden.
- `WerewolfAsh.Games.create_kill_action` (qss.4's `:kill` action, at the arity
  qss.4 defines) — direct tests mirroring `create_action` above: a kill whose
  `actor_id` references another user's seat, or submitted with no actor, is
  forbidden; a werewolf submitting as their own seat is authorized, after
  which qss.4's own rules decide whether the kill is valid. Without this, the
  unnamed `:kill` action would stay `authorize_if always()` under Assumption 5
  and anyone could submit a kill as any wolf.
- **Conditional on qss.21 having landed a `:withdraw` action by
  implementation time; otherwise irrelevant:**
  `WerewolfAsh.Games.withdraw_action/3` — direct test: an actor who does not
  hold the seat named by the `actor_id` argument is forbidden; the actor
  holding that seat is authorized (qss.21's own rules then decide whether
  the withdrawal itself is valid — e.g. voting closed, night already
  started). If `:withdraw` does not exist at implementation time, this item
  does not apply and is not something this bead's coder needs to write.
- `WerewolfAsh.Games.list_actions/0,1`, `WerewolfAsh.Games.get_action/1,2` —
  direct tests: a `:kill` row is readable by a werewolf seat-holder and
  not by a non-wolf game member; an `:investigate` row is readable by the
  seer who cast it and not by any other game member (wolf included); a
  `:protect` row is readable by the bodyguard who cast it and not by any
  other game member, a werewolf included (rule 8, revised 2026-09-13); a
  `:vote` row is readable by any game member; a dead non-wolf, non-seer,
  non-bodyguard game member reads a `:kill` row, an `:investigate` row cast
  by the seer, and a `:protect` row cast by the bodyguard — three tests,
  each paired against the identical setup with that same reader still
  alive, which must still be forbidden, so each assertion pins the "dead
  sees everything" exception specifically and not some other grant (rule 8,
  added 2026-09-13).
- `WerewolfAsh.Games.Action.Changes.ApplyKill.protected?/2`'s internal
  `:protect` lookup gets no new acceptance item of its own: the existing
  `apply_kill_test.exs` "a target protected that day survives and the kill
  is spent" test (see "Existing tests this will break" below) is the pin
  for rule 8's `authorize?: false` fix — it fails without the fix (the
  target dies) and passes with it, no test rewrite needed.
- `WerewolfAsh.Games.send_message/4,5,6`,
  `WerewolfAsh.Games.list_messages_visible_to/1,2,3` — direct tests: the bare
  `:read` action (`Ash.read!(Message, actor: ...)`) no longer returns
  `:wolves`-channel messages to a non-wolf actor; `list_messages_visible_to`
  called with someone else's `player_id` never returns more than the
  caller's own actor-based visibility; sending with `author_id` set to
  another player is forbidden with a policy-class error (not
  `AuthorMayPost`'s validation error); sending as yourself into a channel
  your role doesn't allow is unaffected (still `AuthorMayPost`'s ordinary
  `field: :channel` error).
- `WerewolfAsh.Games.Message.Validations.AuthorMayPost.check/3` — existing
  direct tests keep passing unchanged (rule 12 withdrawn: no wording change).
- End to end, through the domain code interface: start a five-plus-player
  game (qss.3) seating a villager, a werewolf and a dead villager. As the
  villager: read the game and roster (own role visible, others hidden),
  fail to read `:kill` actions, fail to post in `:wolves`. As the
  werewolf: read fellow wolves' roles and `:kill` actions, post in both
  channels. As an outsider holding no seat: every read of the game, its
  players and its messages comes back empty, and both `start_game` and
  `send_message` are forbidden.
- `WerewolfAsh.Accounts.User`'s bare `:read` action — direct test: returns
  nothing for an anonymous actor and for a signed-in actor who shares no
  game with the target (pins rule 13's default-deny); rule 17's grant is
  tested separately below.
- Rule 17's shared-game read grant — direct test: a fellow player of the
  *same* game can read the target user's `:id` and `:name`; a signed-in user
  sharing no game with the target gets nothing; `:email` stays visible only
  on the actor's own row even for a fellow player. A separate test pins the
  field-policy distinction rule 17 itself calls out: a signed-in actor who
  is seated in *no* game at all still reads their own `:name` (and `:email`)
  via `:current_user` — this must keep passing precisely because the
  `:id`/`:name` field policy is unconditional once a row is visible, not a
  second "shares a game" check; this is the existing
  `auth_test.exs`/`describe "setName / currentUser.name"` behavior, unaffected
  by this bead.
- Rule 17's `:email` field policy, the two non-self grants — direct or
  end-to-end tests, since both are load-bearing in production, not just in
  theory: requesting a magic link for an *already-registered* email sends
  the email without `SendMagicLinkEmail.send/3` raising (the existing
  `auth_test.exs` "requestMagicLink succeeds identically..." test already
  exercises this path — see below); `signInWithMagicLink`'s GraphQL response
  includes the signed-in user's real `email` in `result` (already asserted
  by `auth_test.exs:110-111`, `"result" => %{"id" => id, "email" => ^email}`).
- `WerewolfAsh.Accounts.BearerToken.user_from_token/1`, and the `currentUser`
  GraphQL query — test: after
  `AshAuthentication.TokenResource.revoke(WerewolfAsh.Accounts.Token, token)`,
  both return the anonymous/`:error` result for that token.
- `WerewolfAsh.Accounts.User`'s `:current_user` action — direct test:
  anonymous returns nothing without raising; a mismatched actor returns
  nothing; the actor's own id returns their own record (pins whichever of
  rule 15's two shapes is chosen).

### Existing tests this will break

Adding `Ash.Policy.Authorizer` to `Game`, `Player`, `Action` and `Message`
means every existing call to their code interface (or a raw `Ash.read!`/
`Ash.get!`) that supplies no actor and no `authorize?: false` now runs
through the new policies with `actor: nil` — forbidden or filtered to empty
wherever a rule above requires game membership or self-identity. `Player`'s
field policy (rule 5) is not narrower than that: `Helpers.restrict_field_access/2`
is called from `create/create.ex:578`, `update/update.ex:708`,
`destroy/destroy.ex:278` and `read/read.ex` alike, so a single-record
`Ash.create!`/`Ash.update!`/`Ash.destroy!` result is field-policy-filtered
exactly like a read's — `add_player!`/`update_player!`/`join_game!` returning
`role: %Ash.ForbiddenField{}` with no actor is the same rule reaching a
different call shape, not an exception to it. The one thing that is *not* a
problem, so it gets no fix below: a `get`-style read that is genuinely empty
(the row was deleted) looks identical, error-shape-wise, to one a policy
filtered to empty — a test already expecting "not found" needs no change.

None of the fixes below touch the production modules being tested
(`CheckWin`'s `count/1`/`decide/1`, `Visibility`, `AuthorMayPost`'s `check/3`,
`AdvancePhase`, `Clock`, `ResolveLynch`'s `tally/1`/`decide/1` — these last
three already use `authorize?: false` throughout, or (`ResolveLynch`) never
call the domain interface unauthorized to begin with, and need nothing
extra); they thread `authorize?: false` through call sites exercising a
*different* contract than the new policies, exactly as `games_test.exs:32`
already does for loading a `Game`'s `owner`. The genuine production fixes
are `check_win.ex`'s read step, `deal_roles.ex`'s `list_players!` call and
`resolve_game_by_join_code.ex`'s `get_game_by_join_code` call (all three
per rule 4), `apply_kill.ex`'s `protected?/2` read (per rule 8), and —
added this revision, after the spec review found rule 3's original claim
unreachable — `game.ex`'s `validate ActorIsOwner, before_action?: true` on
both `:start` and `:update_settings` (rules 3a/3b), without which the
policy each gains is unreachable for a non-owner/anonymous actor.
`resolve_lynch.ex` needs no production fix at all — it already merged with
`authorize?: false` in place (see rule 8's own entry, settled, not
conditional, in this revision).

- `test/support/generators.ex`'s `player/1`, line 66: the `after_action` hook
  (`Games.update_player!(player, %{role: role})`, added by qss.3 once
  `Player`'s `:create` stopped accepting `role` directly) runs with no
  actor. Its return is what `generate/1`/`generate_many/2` ultimately hand
  back, so under rule 5 every generated player's `.role` comes back
  `%Ash.ForbiddenField{}` instead of the real value — this is the single
  choke point; add `authorize?: false` to that one call and every
  `generate(player(role: ...))`/`generate_many(player(role: ...), n)` call
  site across the suite is fixed without touching them individually. `game/1`
  needs no change: `Game` carries no field policy, and its `:create` stays
  open (rule 2), so field-level auth has nothing to restrict either way.
- `test/werewolf_ash/games_test.exs`, re-grepped fresh against `e6e6158`
  (`grep -n "Games\.\(get_game\|list_players\|get_player\|get_phase\|create_action\|start_game\|add_player\|update_player\|join_game\|get_action\|list_actions\|update_game_settings\|create_phase\|update_phase\)" test/werewolf_ash/games_test.exs`
  — every line number below is fresh, not carried over: the file grew from
  ~690 lines in the previous revision to 1043, gaining a whole
  "day vote resolution (werewolf_ash-qss.5)" describe block (426-488), an
  "update_game_settings" describe block (744-908, qss.14) and an
  "end to end: owner-configured role composition" describe block (910-943,
  qss.14), on top of the qss.3-era blocks this spec already tracked):
  - **"games" (15-180):** line 32,
    `Games.get_game!(game.id, load: [:owner, :players], authorize?: false)`
    ("creates a game with players through the code interface") — **already
    fixed**, not a break: this call already carries `authorize?: false` (the
    comment above it, "User carries a policy authorizer, so loading the
    owner needs authorize?: false here," shows it was added for rule 17's
    `User` grant, but it covers rules 1/4/5 here for free). This corrects
    the previous revision's claim that this test's `get_game!` needed a
    fix — re-verify before assuming either way.
    Line 70, `Games.get_game!(game.id, load: :players).players` ("applies
    sensible defaults...") — needs `authorize?: false` (rule 1); line 72's
    `is_nil(player.role)` depends on the same fix, and rule 5's field
    policy applies to a relationship-loaded `Player` row exactly as it does
    to a direct one. Line 78, `Games.get_game_by_join_code!(game.join_code)`
    ("looks a game up by its join code") — needs `authorize?: false`
    (rule 1); line 79's negative (unknown code) case is unaffected. Nothing
    else in this block reads a Game/Player field this bead governs
    (`update_game`/`create_game` stay open per rule 2, and none of them
    load `:players`/`:owner`).
  - **"phase transitions" (182-424):** the `ready/1` helper (188-193) makes
    no `Games.` call. Every `start_game!`/`start_game` call in this block
    already carries `actor: owner` (200, 253, 269, 278, 291, 305, 314, 325,
    343, 347, 398), except the two negative cases in "requires the owner as
    actor..." below. `end_day!`/`end_night!` calls throughout (214, 228,
    258, 283, 295, 338/341/350's error-case `end_day`/`end_night`) need no
    fix (rule 2). Line 243,
    `Games.get_game!(game.id, load: [:current_phase, :last_phase_number])`
    — needs `authorize?: false` (rule 1). Line 353,
    `Games.get_game!(game.id).state == :day` ("rejects transitions that do
    not match the current state") — needs `authorize?: false` (rule 1).
    **"requires the owner as actor, and leaves every player roleless"
    (357-374):** this test's setup (`ready/0`) already seats 5 players, so
    it is already the "otherwise-valid request" rule 3a's Acceptance
    requires — no setup change needed, only the assertions. Both
    negative-case assertions are stale, not just missing a fix. Replace
    `assert %Ash.Error.Changes.InvalidAttribute{field:
    :owner_id} = error` at line 362 (the no-actor call, 361) and at line
    367 (the `actor: stranger` call, 364-365) with `assert {:error,
    %Ash.Error.Forbidden{errors: [%Ash.Error.Forbidden.Policy{}]}} = ...` —
    rule 3a's policy now forbids both, *and* its `before_action?: true`
    move now runs `ActorIsOwner`'s validation after that policy decides,
    not before it (see rule 3a; verified by running a scratch resource,
    not by reading the source — a coder should not trust the previous
    revision's claim that the policy alone was enough). Line 369,
    `Games.get_game!(game.id).state == :lobby`
    (same test) — needs `authorize?: false` (rule 1). Line 371, the
    `for player <- Games.list_players!(query: [filter: [game_id:
    game.id]]) do` loop (same test) — needs `authorize?: false` (rule 4).
    Line 387, `Games.get_game!(game.id).state == :lobby` ("requires at
    least 5 seated players") — needs `authorize?: false` (rule 1); line 382's
    `start_game` is an error case unrelated to this bead's policies
    (`InvalidChanges`, `MinimumPlayers`, both build-time and unaffected by
    who the actor is — rule 3a does not change this test, since its actor
    is already the owner). **"refuses a configuration the
    seated players cannot satisfy (rule 9)" (390-405):** line 395 calls
    this file's own `update_settings!/2` helper (10-13), which already
    passes `actor: %{id: game.owner_id}` — unaffected by rule 3b's new
    `:update_settings` policy (decisions 7-8), no change. Lines 403-404,
    `Games.list_players!(...) |> Enum.all?(&is_nil(&1.role))` — needs
    `authorize?: false` for the assertion to actually exercise the real
    roster (rules 4/5); note this one does **not** fail outright if left
    unfixed — a policy-filtered `[]` makes `Enum.all?/2` vacuously `true`,
    so the test would pass either way, just not for the reason it claims
    to. **"deals exactly one role to every seated player once the owner
    starts the game" (407-419):** line 410, `Games.start_game!(game, actor:
    owner)` — already correctly actored, but this is the call that reaches
    `DealRoles.deal/2`'s `after_action` hook; if line 28 of
    `deal_roles.ex` is left unfixed, **this line itself raises
    `FunctionClauseError`** (see rule 4's rewritten paragraph for why, and
    why that is a change from the previous revision's description of the
    crash site). Line 414, `Games.list_players!(query: [filter: [game_id:
    game.id]])` feeding `Enum.map(& &1.role) |> Enum.frequencies()` — needs
    `authorize?: false` (rules 4 and 5) for the test to observe the real
    dealt roles; this remains the primary pin for `deal_roles.ex:28`'s own
    fix, alongside `deal_roles_test.exs`'s two tests below. The `phases/1`
    helper (421-423) makes a `Phase` read only — no policy, no fix.
  - **"day vote resolution (werewolf_ash-qss.5)" (426-488) — entirely new
    since the previous revision, not previously audited.** The
    `started_day_game/0` helper (430-441): line 434,
    `Games.start_game!(game, %{now: ...}, actor: owner)` — already
    correctly actored. Line 437, `Games.list_players!(query: [filter:
    [game_id: game.id]]) |> Map.new(&{&1.role, &1})` — needs
    `authorize?: false` (rules 4 and 5): left unfixed, `players` is `%{}`
    and every test below that destructures `p.villager`/`p.werewolf`/etc.
    raises `KeyError`, the same single-choke-point shape as
    `action_test.exs`'s own `started_game/0`. The `open_day_phase/1` helper
    (443): `Games.get_game!(game.id, load: :current_phase).current_phase`
    — needs `authorize?: false` (rule 1). Every `Games.create_action!(day.id,
    p.X.id, p.Y.id, :vote)` call in this block's four tests (449, 450, 462,
    463, 480, 481) — this describe block is testing lynch resolution end to
    end via `end_day!` -> `ResolveDayVote` -> `ResolveLynch`, not rule 7's
    "actions only as yourself," so the same choice this spec already makes
    for `resolve_lynch_test.exs`'s `vote!` helper applies here too: fix
    with `authorize?: false`, not a real per-player actor — using a real
    actor would work too but is not required by any rule this describe
    block exercises. `Games.end_day!(game, %{now: @dusk})` calls (452, 465,
    483) need no fix (rule 2). `Games.get_player!(p.X.id).alive` calls
    (455, 469, 485) — need `authorize?: false` (rule 4; `.alive` carries no
    field policy). `Games.list_phases!(...)` (471) is a `Phase` read — no
    policy, no fix.
  - **"players" (490-625):** setup (491-493) makes no `Games.` call.
    **"adds and removes players one at a time" (495-511):** line 498,
    `Games.add_player!(game.id, alice.id)` — needs `authorize?: false`
    (rule 5: line 502's `is_nil(player.role)` reads the single-record
    create result). Line 505, `Games.list_players!(...) |> length() == 2`
    — needs `authorize?: false` (rule 4). Line 507, `Games.remove_player!`
    — no fix (rule 6). Line 509, `Games.list_players!(...) |>
    Enum.map(& &1.user_id) == [game.owner_id]` — needs `authorize?: false`
    (rule 4). **"a user can only hold one seat per game" (513-523)** and
    **"rejects role as an unrecognized input" (525-529):** no fix — every
    call only reads `.user_id`/is an error case, neither governed by rule 5.
    **"a seat can be given up while the game is in the lobby" (531-536):**
    no fix — `Games.get_player(player.id)` at 535 is genuinely not-found
    after a real `remove_player`. **"a seat cannot be given up once the
    game has left the lobby" (538-547):** line 540, `[player | _] =
    Games.list_players!(...)` — needs `authorize?: false` (rule 4). Line
    542, `start_game!(game, actor: owner)` — already actored. Line 546,
    `Games.get_player!(player.id).id` — needs `authorize?: false` (rule 4;
    `.id` is always field-visible, but the row is invisible without this
    fix). **"updates role and aliveness" (549-559):** line 552,
    `Games.update_player!(player, %{role: :seer})` feeding `player.role ==
    :seer` — needs `authorize?: false` (rule 5). Line 555,
    `Games.update_player!(player, %{alive: false})` feeding
    `refute player.alive` — no fix (`.alive` has no field policy). **"are
    deleted along with their game" (561-566):** line 565,
    `Games.list_players!(...) == []` — needs `authorize?: false` (rule 1):
    with no actor the read policy returns `[]` whether or not the players
    were deleted, so the assertion would pass vacuously. **The three 27w.9 nameless/named/shared-name
    tests (568-592):** the "refuses" test's follow-up `list_players!`
    (575) needs `authorize?: false` (rule 1): the seat is never created,
    but with no actor the read returns `[]` either way, so without the
    fix the assertion passes vacuously; the others only read
    `.user_id`/`.id` off `add_player!`/`join_game!` results and need no fix. **"accepts
    add_player below max_players (rule 16)" (594-600)** and **"add_player
    is never refused on max_players when it is nil" (618-624)** — no fix
    (only `.user_id` read; `update_settings!` at 595 already actored).
    **"refuses add_player once max_players is already seated (rule 16)"
    (602-616) — new since the previous revision (qss.14).** Line 603,
    `update_settings!` — already actored. Line 615, `Games.list_players!(...)
    |> length() == 4` — needs `authorize?: false` (rule 4).
  - **"join_game" (627-742) — every `join_game`/`join_game!` call site in
    this block re-verified this revision against rule 4's production fix
    (`authorize?: false` on `resolve_game_by_join_code.ex:20`), not just
    against rules 5/6 as before.** Without that fix, every single one of
    these calls fails with `:join_code` "does not match any game" — none
    of the classifications below is "no fix" *in spite of* that; they are
    "no *test* fix," because the production fix in rule 4 is what keeps
    every one of these calls succeeding exactly as it does today, and none
    of them needs `authorize?: false`/`actor:` added at the *call site*
    itself, unlike a `Games.get_game`/`Games.list_players` read. Line 632,
    `Games.join_game!(game.join_code, user.id)` feeding line 636's
    `is_nil(player.role)` ("seats a user...") — needs `authorize?: false`
    on this call (rule 5, unrelated to rule 4's fix: the field policy on
    the returned `Player`'s `.role`). Line 654 (`named.id`, "seats a named
    user via join...") and lines 663-664 (`alice.id`/`bob.id`, "two players
    may share...") — no fix: each only reads `.user_id`/`.id` off the
    return, neither governed by rule 5. Line 703 ("joining twice fails...")
    and lines 929-930 (the "end to end: owner-configured role composition"
    describe block's two seating calls) — no fix: the return is discarded
    in all three. "an unknown join_code..." (668-677) and "rejects role as
    an unrecognized input..." (692-698) — no fix: both pass with or
    without rule 4's `ResolveGameByJoinCode` fix. "a join_code for a game
    that has already left the lobby..." (679-690, `ready()`/`start_game!`
    at 680-681 already actored) — no test change, but it depends on that
    fix: without it the lookup's own `:join_code` error
    (`InvalidAttribute`, as the unknown-code test shows) comes back instead
    of, or alongside, the `InvalidArgument` the test matches, so
    `errors: [error]` fails. "refuses to seat a nameless user..." (639-648)
    — the `join_game` call needs no change but depends on the same fix
    (without it the lookup's `:join_code` error joins the `:name` error
    and `errors: [error]` no longer matches); line 647,
    `Games.list_players!(query: [filter: [user_id: nameless.id]]) == []`,
    needs `authorize?: false` (rule 1): with no actor the read policy
    returns `[]` whether or not a player was created, so the assertion
    would pass vacuously.
    Line 716 ("accepts a join below max_players (rule 11)") and line 739
    ("a join is never refused on max_players when nil") — no fix
    (`update_settings!` at 713/already actored where relevant; only
    `.user_id` read). **"refuses a join once
    max_players is already seated (rule 11)" (720-732) — new since the
    previous revision (qss.14).** Line 722, `update_settings!` — already
    actored. Line 731, `Games.list_players!(...) |> length() == 4` — needs
    `authorize?: false` (rule 4).
  - **"update_game_settings" (744-908) — entirely new since the previous
    revision (qss.14), and the one describe block rule 3b's own creation
    reaches directly.** "the owner may change any
    subset..." (745-759), "rejects a change once the game has already left
    the lobby (rule 3)" (773-781, qss.14's own rule numbering, not this
    spec's — that test's actor is already the owner, so rule 3b changes
    nothing about it: the game is deliberately *not* an otherwise-valid
    request there, and `attribute_equals(:state, :lobby)` stays build-time,
    so it still fires first regardless of actor), "rejects nil for any of
    the five non-nullable settings (rule 1)" (783-789), "rejects an
    attribute outside the seven settings..." (791-797), "enforces rules 4-7
    through the action" (799-845), "rule 17: setting max_players exactly
    equal..." (875-894) and "rule 17: max_players left nil is never
    refused..." (896-903) — no fix: every call already passes `actor:
    owner`, and `Game` carries no field policy, so nothing read off an
    `update_game_settings!` result is gated by anything this bead adds.
    **"rejects a caller other than the game's own owner (rule 2)"
    (761-771) — stale, not just missing a fix.** Its setup (a freshly
    generated game, `state: :lobby`, `max_players: 6` alone) is already an
    otherwise-valid request, so it needs no setup change. Line 767,
    `Games.update_game_settings(game, %{max_players: 6}, actor: stranger)`
    — line 769's `assert %Ash.Error.Changes.InvalidAttribute{field:
    :owner_id} = error` must become `assert {:error, %Ash.Error.Forbidden{
    errors: [%Ash.Error.Forbidden.Policy{}]}} = ...`, the identical change
    rule 3a makes to `start_game`'s equivalent test, and for the identical
    reason: rule 3b's policy now forbids this, *and* its `before_action?:
    true` move on `:update_settings`'s own `ActorIsOwner` validation is
    what actually lets the policy's answer win — without that move, this
    stranger call would still resolve to the validation's `Invalid`, not
    the policy's `Forbidden` (verified by running a scratch resource; see
    rule 3a). Line 770, `Games.get_game!(game.id,
    authorize?: false)` — already fixed, no change. This test still has no
    case for "no actor at all" — the Acceptance section above adds that as
    a new test, since no existing call anywhere in the suite calls
    `update_game_settings` with no actor. **"rule 17: refuses to set
    max_players below the seated count" (847-873):** line 868,
    `Games.list_players!(...) |> length() == 3` — needs `authorize?: false`
    (rule 4); line 869's `Games.get_game!(game.id, authorize?: false)` is
    already fixed.
  - **"end to end: owner-configured role composition" (910-943) — entirely
    new since the previous revision (qss.14).** Lines 914-932
    (`create_game!`, `update_game_settings!` at 922 already actored,
    `join_game!`/`add_player!`) need no fix — none of them read a
    field-policy-governed value off their own return. Line 934,
    `Games.start_game!(game, actor: owner)` — already correctly actored;
    like the "phase transitions" block's "deals exactly one role..." test,
    this call reaches `DealRoles.deal/2` and would also raise
    `FunctionClauseError` if `deal_roles.ex:28` is left unfixed (this
    game's settings — manual mode, 2 wolves, seer disabled, bodyguard/hunter
    left at their `true` defaults — make `villagers` negative on an empty
    roster the same way the default-settings case does); this is a
    secondary observation, not a second required pin, since the "phase
    transitions" test already covers rule 4's own Acceptance item. Line 937,
    `Games.list_players!(query: [filter: [game_id: game.id]])` feeding
    `Enum.map(& &1.role) |> Enum.frequencies()` at line 938 — needs
    `authorize?: false` (rules 4 and 5).
  - **"phases" (945-985):** `create_phase!`/`create_phase`/`update_phase!`
    calls (951, 952, 964, 970, 973, 977, 980) — `Phase` carries no policy,
    no fix. Line 959, `Games.get_game!(game.id, load: :phases).phases |>
    Enum.map(& &1.id)` ("are numbered per game and listed in order") —
    needs `authorize?: false` (rule 1).
  - **"actions" (987-1042):** setup (988-992) seats players via
    `Games.add_player!` (no field-governed read off the return) and calls
    `Games.create_phase!` (`Phase`, no policy) — no fix. Line 995,
    `Games.create_action!(ctx.phase.id, ctx.alice.id, ctx.bob.id, :vote)`
    ("records who did what to whom in a phase") — needs `authorize?: false`
    (rule 7; this describe block tests `Action`'s own CRUD/relationships,
    not rule 7's impersonation check, so `authorize?: false` is the right
    fix here, the same choice as the "day vote resolution" block above,
    not the real-actor choice `action_test.exs` makes). Line 1000,
    `Games.update_action!` — no fix (rule 9, stays open). Line 1003,
    `Games.get_player!(ctx.alice.id, load: [:performed_actions,
    :targeted_by_actions])` — needs `authorize?: false` for the `Player`
    read (rule 4) *and* because the loaded relationships are `Action` reads
    (rule 8). Line 1008, `Games.get_player!(ctx.bob.id, load:
    [:targeted_by_actions])` (same test) — same fix, same reasons. Line
    1011, `Games.get_phase!(ctx.phase.id, load: :actions).actions` (same
    test) — `Phase` itself carries no policy, but the loaded `:actions`
    relationship is an `Action` read; needs `authorize?: false`. Line 1015,
    `Games.create_action!(...)` ("allows one action per actor, phase and
    type") — needs `authorize?: false` (rule 7). Lines 1017-1018,
    `Games.create_action(ctx.phase.id, ctx.alice.id, ctx.alice.id, :vote)`
    (same test, expects the duplicate-identity error at `field:
    :phase_id`) — needs `authorize?: false` (rule 7): without it this is
    forbidden before the identity check runs, changing the expected error
    class. Line 1021, `Games.update_player!(ctx.alice, %{role:
    :bodyguard})` (same test, return discarded) — no fix. Line 1024,
    `Games.create_action!(...)` (same test) — needs `authorize?: false`
    (rule 7). Line 1028, `Games.create_action!(day2.id, ...)` (same test)
    — needs `authorize?: false` (rule 7). Lines 1032-1033,
    `Games.create_action(ctx.phase.id, ctx.alice.id, ctx.bob.id, :dance)`
    ("rejects unknown types") — needs `authorize?: false` (rule 7), for the
    same reason as 1017-1018. Line 1037, `Games.create_action!(...)` ("are
    deleted along with their phase") — needs `authorize?: false` (rule 7).
    Line 1040, `Games.get_action(action.id)` (same test) — no change, the
    action is genuinely gone (its phase was destroyed).
  - Nothing else in this file changes: every `create_game`/`update_game`/
    `destroy_game` call, and the top-of-file `update_settings!/2` private
    helper (10-13, already `actor: %{id: game.owner_id}`, unaffected by
    rule 3b) stay as-is.
- `test/werewolf_ash/games/action/changes/apply_kill_test.exs` (69 lines,
  unchanged in shape since the previous revision — re-grepped fresh against
  `e6e6158`, same result:
  `grep -n "Games\." test/werewolf_ash/games/action/changes/apply_kill_test.exs`
  → 38, 49, 54, 66):
  - Lines 38, 54 and 66, `Games.get_player!(target.id).alive` (three tests
    under `describe "change/3"`) — need `authorize?: false` (rule 4; `.alive`
    carries no field policy, so rule 5 does not additionally apply here).
  - Line 49, `Games.create_action!(day.id, bodyguard.id, target.id,
    :protect)` — needs `authorize?: false` (rule 7).
  - Line 21's `stage/3` helper calls `ApplyKill.change/3` directly with
    `context: %{}`, then invokes the returned `after_action` hook itself —
    it never goes through the real `:kill` action, so `Context.to_opts(%{})`
    (`Ash.Scope.to_opts/2`, `deps/ash/lib/ash/scope.ex:107-123`, its `Map`
    impl at `deps/ash/lib/ash/scope.ex:189-203`) resolves to `[]`: no actor,
    no `authorize?` key. Every read inside `protected?/2` therefore runs
    with the domain's own `authorize: :by_default` default
    (`deps/ash/lib/ash/actions/helpers.ex:394-395`, `Keyword.put_new(opts,
    :authorize?, true)`) and `actor: nil`. This is a second, independent
    reason (on top of rule 8's forced consequence above) that "a target
    protected that day survives and the kill is spent" is the pin for the
    `apply_kill.ex:43-59` fix, not just a nice-to-have: with `actor: nil`,
    rule 8's own *baseline* already returns nothing for any `Action` read,
    narrowed or not, so this test would fail on the unnarrowed baseline
    too, before rule 8's `:protect`-specific narrowing is even reached. The
    single `authorize?: false` fix specified under rule 8 covers both
    reasons at once, since it stops this read from depending on `opts` (and
    therefore on the actor) at all — no separate fix or test change is
    needed here beyond the four calls already listed above.
- **Seven `Action`-validation test files need no change**, checked fresh
  against `e6e6158` — four from qss.4 (`actor_alive_test.exs`,
  `type_requires_phase_and_role_test.exs`,
  `shoot_requires_pending_hunter_test.exs`,
  `changes/record_investigation_result_test.exs`) and three new ones from
  qss.18 (`actor_and_target_in_game_test.exs`, `no_consecutive_protect_test.exs`,
  `target_alive_test.exs`)
  (`grep -n "Games\." test/werewolf_ash/games/action/validations/*.exs test/werewolf_ash/games/action/changes/record_investigation_result_test.exs`
  → only `Games.update_player!(actor_or_hunter, %{alive: false})`-shaped
  calls in `actor_alive_test.exs`, `shoot_requires_pending_hunter_test.exs`
  and `target_alive_test.exs`, every one a discarded-return setup call, no
  fix needed (rule 6); `actor_and_target_in_game_test.exs`,
  `no_consecutive_protect_test.exs`, `type_requires_phase_and_role_test.exs`
  and `record_investigation_result_test.exs` have no `Games.` calls at all)
  — none of these seven creates or reads an `Action` through the domain
  interface; they call the validation/change modules directly on bare
  changesets/structs, the same pattern as `AuthorMayPost`'s own tests.

**No forced consequence found in `Player.Validations.UserHasName`.** This is
qss.4/27w.9's `Player`-seating validation (`lib/werewolf_ash/games/player/validations/user_has_name.ex`),
the same shape of risk as `CheckWin`'s and `deal_roles.ex`'s reads (an
actor-less lookup of a resource this bead adds a policy to) — re-checked
against `e6e6158`. It already reads with `Ash.get(User, user_id,
authorize?: false)` (line 28), and its own moduledoc says why: "The user is
looked up without authorization: this is a game rule, not an access check...
the same convention `Message.Validations.AuthorMayPost` uses." No production
fix is needed here, and no new test needs writing — both existing test files
already pass regardless of this bead: `user_has_name_test.exs` calls
`UserHasName.validate/3` directly on a manually-built changeset (never
through an authorized action, so `User`'s new policies never run), and
`games_test.exs`'s "refuses to seat a nameless user"/"seats a named user"
tests (568-576, 578-583 in the "players" block; 639-648, 650-656 in the
"join_game" block) call `Player`'s `:create`/`:join` with no actor, and
`UserHasName` never causes them to fail, since its own `Ash.get/3` already
bypasses authorization. The two "join_game" tests still depend on rule 4's
`ResolveGameByJoinCode` fix, and lines 575 and 647 need `authorize?: false`
so their `== []` assertions are not vacuous (see the "players" and
"join_game" entries above).

**`test/werewolf_ash/games/action_test.exs` — re-audited in full against
`e6e6158`; grown from 356 to 485 lines since the previous revision (qss.18
added new tests inline, qss.20 tightened two assertions), so every line
number below has moved and every new call site needs its own
classification**
(`grep -n "Games\." test/werewolf_ash/games/action_test.exs` — 106 hits;
`grep -n "actor:" test/werewolf_ash/games/action_test.exs` → line 22 only,
confirming every `create_action`/`create_kill_action` call in the file
still has zero actor, same as the previous revision found):

Four groups, same shape as before, updated line numbers, plus qss.18's new
call sites folded into groups 2 and 3:

1. **No fix**: `end_day!`/`end_night!` (65, 96, 119, 159, 160, 171, 185,
   199, 250, 251, 269, 400, 401, 410, 411, 429, 462) — `Game`'s
   `:end_day`/`:end_night` stay open (rule 2). `update_player!` (82, 99,
   100, 101, 122, 293, 315, 342, 474) — `Player`'s `:update` stays open
   (rule 6) and none of these nine read `.role`/any field-policy-governed
   value off the return. Line 22's `start_game!` already carries
   `actor: owner`.

2. **`started_game/0` and `current_phase/1`, the file's two setup helpers
   — `authorize?: false`, not a real actor** (unchanged reasoning from the
   previous revision):
   - Line 25, `started_game/0`'s `Games.list_players!(...)` — needs
     `authorize?: false` (rules 4 *and* 5: line 26's `Map.new(&{&1.role,
     &1})` reads `.role` off this same result, and line 28's
     `assert map_size(players) == 5` — qss.20's own tightened assertion —
     fails immediately if left unfixed, since `players` would be `%{}`).
   - Line 34, `current_phase/1`'s `Games.get_game!(game.id, load:
     :current_phase).current_phase` — needs `authorize?: false` (rule 1).

3. **Every `create_action`/`create_kill_action` call — `actor:`, the
   submitting player's own `User`, not `authorize?: false`** (unchanged
   reasoning: this file is qss.4/qss.18's own action-creation rules test,
   so masking rule 7 with `authorize?: false` would make every test here
   pass regardless of it). `started_game/0` must expose each player's own
   `User` alongside the `Player` it already tracks (e.g. resolving
   `player.user_id` via `Ash.get!(WerewolfAsh.Accounts.User, player.user_id,
   authorize?: false)` per player); the same exposure is needed for the
   ad-hoc `other_wolf`/`outsider_wolf`/`outsider` players generated inline
   at lines 143, 328-329 and 359 (an `outsider`'s own `User` — not any
   player from `started_game`'s roster — is the correct actor for a
   cross-game call naming that outsider as the acting player; the
   *target*-side outsider calls, e.g. line 146, still act as `p.villager`).
   Every line needing this fix: 52, 68, 76, 86, 104, 107, 110, 125, 128,
   131, 146, 149, 157, 164, 167, 175, 188, 191, 202, 205, 212, 220, 228,
   231, 241, 245, 248, 254, 261, 275, 288, 291, 296, 306, 308, 318, 332,
   335, 345, 347, 358, 362, 365, 379, 398, 405, 408, 415, 422, 423, 427,
   433, 436, 441, 445, 448, 460, 465, 478, 482 — 60 call sites total,
   including qss.18's new tests ("rejects a cross-game actor or target,"
   "rejects consecutive-day protection...," "rejects a dead target,"
   "rejects a dead-target kill...," each of which is new since the
   previous revision but follows the identical shape).

4. **Every remaining read verifying state after the fact —
   `authorize?: false`, same reasoning as group 2.** `get_action!` (55,
   233, 367), `list_actions!` (57, 112, 113, 133, 134, 151, 177, 298, 320,
   337, 452), `get_player!` (279, 311, 350, 370, 371, 439, 450, 468) — all
   need `authorize?: false`. (151, 320, 337 and the "rejects a dead
   target"/"rejects a cross-game actor and target" tests these belong to
   are new since the previous revision; the fix is the same as every other
   entry in this group.)

`Ash.Seed.seed!` (lines 383-389, "the database refuses a second kill row
even bypassing the application") needs no change: seeding writes straight to
the data layer, bypassing Ash actions and policies entirely, which is the
point of that test.

**Provenance for this revision:** `git diff --stat 034a775..e6e6158 --
test/` (034a775 is the commit the previous revision was written against)
lists 16 files, 1440 insertions:

```
$ git diff --stat 034a775..e6e6158 -- test/
 .../validations/actor_and_target_in_game_test.exs  |  67 ++++
 .../validations/no_consecutive_protect_test.exs    | 106 +++++++
 .../games/action/validations/target_alive_test.exs |  44 +++
 test/werewolf_ash/games/action_test.exs            | 133 +++++++-
 .../games/game/changes/resolve_day_vote_test.exs   |  89 ++++++
 .../games/game/role_assignment_test.exs            |  68 +++-
 .../validations/composition_fits_at_cap_test.exs   |  56 ++++
 .../manual_werewolf_count_valid_test.exs           |  32 ++
 .../max_players_not_below_seated_test.exs          |  51 +++
 .../game/validations/min_not_above_max_test.exs    |  27 ++
 .../game/validations/minimum_players_test.exs      |  20 ++
 .../validations/positive_player_bounds_test.exs    |  31 ++
 .../validations/role_composition_fits_test.exs     |  75 +++++
 .../player/validations/game_not_full_test.exs      |  85 +++++
 .../games/reactors/resolve_lynch_test.exs          | 211 ++++++++++++
 test/werewolf_ash/games_test.exs                   | 353 ++++++++++++++++++-
 16 files changed, 1440 insertions(+), 8 deletions(-)
```

`action_test.exs` and `games_test.exs` are covered above in full. The
remaining 14 are handled below; ten of them (`role_assignment_test.exs`,
`composition_fits_at_cap_test.exs`, `manual_werewolf_count_valid_test.exs`,
`max_players_not_below_seated_test.exs`, `min_not_above_max_test.exs`,
`positive_player_bounds_test.exs`, `actor_and_target_in_game_test.exs`,
`no_consecutive_protect_test.exs`, `target_alive_test.exs` and — already
covered above — the other four qss.18/qss.4 validation test files) call
their validation/pure-function module directly and need no change; that is
confirmed by grep, not assumed, for every one of them below. Every file
*not* in this diff — `deal_roles_test.exs`, `check_win_test.exs`,
`resolve_win_test.exs`, `message_test.exs`, `visibility_test.exs`,
`preparations/visible_to_test.exs`, `author_may_post_test.exs`,
`auth_test.exs`, `actor_is_owner_test.exs`, `game_in_lobby_test.exs`,
`user_has_name_test.exs` — is confirmed unchanged since the previous
revision by the same diff, and by re-running each file's own grep fresh
against `e6e6158`: every line number in that cluster is unchanged from the
previous revision.

- `test/werewolf_ash/games/game/changes/deal_roles_test.exs`
  (`grep -n "Games\.\(list_players\|get_player\)" test/werewolf_ash/games/game/changes/deal_roles_test.exs`
  → 23, 35, 43; unchanged line numbers, both tests):
  - Line 23, `Games.list_players!(query: [filter: [game_id: game.id]])`
    (feeding line 24's `.role` frequencies) — needs `authorize?: false`
    (rules 4 and 5). This is the other existing pin for `deal_roles.ex:28`'s
    own forced-consequence fix (see rule 4's rewritten paragraph and the
    games_test.exs entry above): fix this line alone and the test calls
    `DealRoles.change/3`'s `after_action` hook directly at line 20, so it
    still fails if `deal_roles.ex:28` isn't also fixed — `FunctionClauseError`
    from `List.duplicate/2` inside `composition/2`, not from `composition/1`'s
    former `>= 5` guard (that guard no longer exists; see rule 4). The
    empty roster is still the bug, not the guard's absence.
  - Line 35, `Games.list_players!(query: [filter: [game_id: other_game.id]])`
    — needs `authorize?: false` (rule 4).
  - Line 43, `Games.get_player!(other_player.id).role` — needs
    `authorize?: false` (rules 4 and 5).
- `test/werewolf_ash/games/reactors/check_win_test.exs`
  (`grep -n "Games\.get_game!" test/werewolf_ash/games/reactors/check_win_test.exs`
  → line 106 only, unchanged): "never touches the game"'s
  `Games.get_game!(game.id)` needs `authorize?: false` (rule 1).
  `check_win.ex`'s own `read :living_players` step fix is rule 4's forced
  consequence, not a separate item — see rule 4.
- `test/werewolf_ash/games/reactors/resolve_win_test.exs`
  (`grep -n "Games\.\(get_game\|list_players\|start_game\)" test/werewolf_ash/games/reactors/resolve_win_test.exs`
  → 18, 20, 33, 44, 53, 62, 73; unchanged line numbers):
  - Line 33, `Games.get_game!(game.id)` ("leaves a game alone...") — needs
    `authorize?: false` (rule 1).
  - Line 44, `Games.list_players!(...) |> Enum.find(&(&1.role ==
    :werewolf))` ("finishes the game for the village") — needs
    `authorize?: false` (rules 4 and 5).
  - Line 53, `Games.get_game!(game.id).winner` (same test) — needs
    `authorize?: false` (rule 1).
  - Line 62, `Games.list_players!(...) |> Enum.split_with(&(&1.role ==
    :werewolf))` ("finishes the game for the wolves") — needs
    `authorize?: false` (rules 4 and 5).
  - Line 73, `Games.get_game!(game.id).state` (same test) — needs
    `authorize?: false` (rule 1).
  - Line 18 (`load: :owner, authorize?: false`) and the `start/1` helper's
    `Games.start_game!(game, actor: owner)` are already correct; no change.
- **`test/werewolf_ash/games/reactors/resolve_lynch_test.exs` (211 lines,
  entirely new since the previous revision, qss.5) — not previously
  audited**
  (`grep -n "Games\." test/werewolf_ash/games/reactors/resolve_lynch_test.exs`
  — 18 hits: the `vote!/3` helper's own definition at line 21 (containing
  the literal `Games.create_action!` the grep matches — the helper's own
  16 *call sites* elsewhere in the file do not match this grep at all,
  since they call the local `vote!(...)` function, not anything prefixed
  `Games.`), one more direct `Games.create_action!` (line 141), two
  `Games.update_player!` calls (182, 204), and 14 `Games.get_player!(...).alive`
  calls):
  - Line 21, `defp vote!(day, actor, target), do: Games.create_action!(day.id,
    actor.id, target.id, :vote)` — needs `authorize?: false` (rule 7). This
    file tests lynch resolution, not rule 7's impersonation check (that is
    `action_test.exs`'s job), so `authorize?: false` is the right fix here,
    the same choice this spec already makes for `message_test.exs`'s
    `post!`/`post` helpers under rule 11. Fixing this one line covers every
    one of `vote!/3`'s 16 call sites (lines 90, 91, 107, 108, 122, 123, 142,
    143, 161, 162, 178, 179, 180, 200, 201, 202) without touching them
    individually — none of those 16 lines themselves need editing, and
    none of them appears in the grep count above.
  - Line 141, `Games.create_action!(day.id, bodyguard.id, target.id,
    :protect)` ("an existing :protect action for the lynched player does
    not save them") — needs `authorize?: false` (rule 7), same reasoning.
  - Lines 182 and 204, `Games.update_player!(voter_a1/target_c, %{alive:
    false})` — no fix (rule 6, `Player`'s `:update` stays open; neither
    reads `.role` off the return).
  - Every `Games.get_player!(...).alive` call (14 total: 94, 95, 96, 113,
    126, 127, 128, 146, 165, 166, 185, 186, 207, 208) — needs
    `authorize?: false` (rule 4; `.alive` carries no field policy).
- **`test/werewolf_ash/games/game/changes/resolve_day_vote_test.exs` (89
  lines, entirely new since the previous revision, qss.5) — not previously
  audited**
  (`grep -n "Games\." test/werewolf_ash/games/game/changes/resolve_day_vote_test.exs`
  — 12 hits, 8 of them `get_*`/`list_*`):
  - Lines 44, 45, 70, 71, `Games.create_action!(day.id, ..., :vote)` (two
    votes per test, staged before `stage_hooks/2` builds the `:end_day`
    changeset) — need `authorize?: false` (rule 7), same reasoning as
    `resolve_lynch_test.exs`'s `vote!` helper above: this file tests
    `ResolveDayVote`'s change, not rule 7.
  - Lines 51, 59, 78 — `Games.list_phases!(...)` — `Phase` carries no
    policy, no fix.
  - Lines 60, 82 — `Games.get_phase!(...)` — `Phase`, no fix.
  - Lines 57, 85, 86 — `Games.get_player!(wolf/villager1.id).alive` — need
    `authorize?: false` (rule 4).
  - `stage_hooks/2`'s own `Changeset.for_update(game, :end_day, %{now: now},
    authorize?: false)` (line 30) is already correct; no change.
- `test/werewolf_ash/games/message_test.exs`
  (`grep -n "Games\.\(send_message\|list_messages_visible_to\)" test/werewolf_ash/games/message_test.exs`
  → 34, 38, 43, 88, 91, 149, 150, 154, 162; unchanged since the previous
  revision):
  - `post!/1,3` (line 33-35) and `post/1,3` (37-39) — add `authorize?: false`
    (rule 11).
  - `visible_ids/1,2` (41-45) — add `authorize?: false` (rule 10).
  - Line 88 and line 91, the two direct `Games.send_message(...)` calls in
    "the author must be a player of the game" (outside the `post`/`post!`
    helpers) — need `authorize?: false` (rule 11), or every actor-less call
    is forbidden before `AuthorMayPost` ever runs, regardless of which
    `author_id` was passed.
  - Line 149 and line 150, the two direct `Games.list_messages_visible_to!`
    calls in "messages never cross games..." — need `authorize?: false`
    (rule 10).
  - Line 154, `Games.list_messages_visible_to!(ctx.dead_wolf.id)` ("messages
    come back oldest first") — needs `authorize?: false` (rule 10).
  - Line 162, `Games.list_messages_visible_to!(ctx.villager.id, load:
    :author)` ("the author can be loaded") — needs `authorize?: false`
    (rule 10 for the `Message` read, and rule 4 for the loaded `:author`
    `Player`).
  - `messages_in/1`'s `Ash.read!()` (line 188) — needs `authorize?: false`
    (rule 10).
  - `test/werewolf_ash/games/message/validations/author_may_post_test.exs`:
    **no change** — it exercises `check/3`/`validate/3` on bare structs and
    a manually-built changeset, never through an authorized action.
- `test/werewolf_ash/games/message/visibility_test.exs`
  (`grep -n "Games\.send_message\|Ash\.read!" test/werewolf_ash/games/message/visibility_test.exs`
  → 24, 25, 39; unchanged): the `setup` block's two `Games.send_message!`
  calls (24-25) need `authorize?: false` (rule 11); `visible_message_ids/1`'s
  `Ash.read!()` (line 39) needs it too (rule 10).
- `test/werewolf_ash/games/message/preparations/visible_to_test.exs`
  (`grep -n "Games\.send_message\|Ash\.read!" test/werewolf_ash/games/message/preparations/visible_to_test.exs`
  → 18, 31, 36; unchanged): the `setup` block's `Games.send_message!` call
  (line 18) needs `authorize?: false` (rule 11); the two `Ash.read!()`
  calls in the test bodies (31 and 36) need it too (rule 10) —
  `prepared_query/1` only builds the query, the read happens at the call
  site.
- `test/werewolf_ash_web/graphql/auth_test.exs` — re-read in full against
  `e6e6158`; unchanged since the previous revision (not touched by
  qss.18/14/5):
  - Lines 110-111, `"result" => %{"id" => id, "email" => ^email}` inside
    "request -> sign in -> authenticated currentUser, registering a new
    user on first use" — needs the `action(:sign_in_with_magic_link)` grant
    (rule 17), or `email` renders as forbidden/`nil` and the pattern match
    fails.
  - Lines 154-171, "requestMagicLink succeeds identically for an
    unregistered email as for a registered one" — the second
    `requestMagicLink` call at line 165 requests a link for
    `registered_email`, which by then *is* registered (signed in at line
    157), landing in `Request.run/3`'s `{:ok, user}` branch
    (`sender.send(user, ...)`); needs the `AshAuthenticationInteraction`
    grant (rule 17), or `SendMagicLinkEmail.send/3` raises trying
    `to_string/1` on a forbidden `:email`.
  - The four `setName`/`currentUser.name` tests all sign in a real user
    first and act as that same actor throughout, so `:set_name`'s and
    `:current_user`'s own pre-existing policies already cover them; the one
    anonymous case already expects an `errors` entry regardless of reason.
    Every other `SendMagicLinkEmail`/`magic_link_url` test calls those
    modules' functions directly on bare structs/strings, never through an
    authorized action. Add the new token-revocation test here (rule 14).
- **`test/werewolf_ash/games/game/validations/minimum_players_test.exs`
  (+20 lines since the previous revision, qss.14) — no change**, but worth
  recording since it now calls the domain interface where it didn't
  before: lines 37 and 43,
  `Games.update_game_settings!(game, %{min_players: N}, actor: %{id:
  game.owner_id})` — already correctly actored for rule 3b (decisions
  7-8); `MinimumPlayers.validate/3` itself is called directly on a
  bare changeset (`authorize?: false`), never through an authorized action.
- **`test/werewolf_ash/games/game/validations/role_composition_fits_test.exs`
  (new, qss.14) — no change**: every `Games.update_game_settings!` call
  (lines 36, 46, 60) already passes `actor: %{id: game.owner_id}`;
  `RoleCompositionFits.validate/3` is called directly on a bare changeset.
- **`test/werewolf_ash/games/player/validations/game_not_full_test.exs`
  (new, qss.14) — no change**: the one `Games.update_game_settings!` call
  (line 65) already passes `actor: %{id: game.owner_id}`;
  `GameNotFull.validate/3` is called directly on a bare changeset.
- **`test/werewolf_ash/games/game/role_assignment_test.exs`,
  `test/werewolf_ash/games/game/validations/composition_fits_at_cap_test.exs`,
  `manual_werewolf_count_valid_test.exs`, `max_players_not_below_seated_test.exs`,
  `min_not_above_max_test.exs`, `positive_player_bounds_test.exs`,
  `test/werewolf_ash/games/game/changes/advance_phase_test.exs`,
  `test/werewolf_ash/games/game/validations/actor_is_owner_test.exs`,
  `test/werewolf_ash/games/player/validations/game_in_lobby_test.exs` — no
  change**, confirmed by grep for any `Games.`/`Ash.` call in each
  (`grep -n "Games\.\|Ash\." <file>` for every file in this bullet): none
  makes a domain-interface call at all; each exercises its own
  validation/pure-function module directly (`RoleAssignment.composition/2`,
  `CompositionFitsAtCap.validate/3`, `ManualWerewolfCountValid.validate/3`,
  `MaxPlayersNotBelowSeated.validate/3`, `MinNotAboveMax.validate/3`,
  `PositivePlayerBounds.validate/3`, `AdvancePhase.change/3`,
  `ActorIsOwner.validate/3`, `GameInLobby.check/3`) on bare
  changesets/structs.

## Touches

Advisory only.

- `lib/werewolf_ash/games/game.ex` — `authorizers: [Ash.Policy.Authorizer]`,
  a `policies do` block for rules 1, 2, 3a and 3b (the owner-only policy on
  both `:start` and `:update_settings`); and, the production change rules
  3a/3b both require, `validate ActorIsOwner, before_action?: true` on
  both the `:start` and `:update_settings` action blocks (in place of the
  plain `validate ActorIsOwner` each has today) — without this, the policy
  added above is unreachable for a non-owner/anonymous actor (verified by
  running a scratch resource, see rule 3a; this is a real change to
  existing production code, not just new code).
- `lib/werewolf_ash/games/player/changes/resolve_game_by_join_code.ex:20` —
  `authorize?: false` added to its `Games.get_game_by_join_code(join_code)`
  call (rule 4's third forced consequence); without this, every `:join`
  fails once `Game` gains its read policy, regardless of rule 6 leaving
  `Player`'s own `:join` policy open.
- `lib/werewolf_ash/games/player.ex` — `authorizers: [...]`, `policies do`
  for rules 4/6, `field_policies do` for rule 5, including the `:finished`
  condition and the "dead sees everything" condition (both added
  2026-09-13), each crossing the existing `belongs_to :game`/`has_many
  :players` relationships.
- `lib/werewolf_ash/games/action.ex` — `authorizers: [...]`, `policies do`
  for rules 7-9, including rule 8's `:protect`-narrowing condition and its
  "dead sees everything" exception (both added/revised 2026-09-13)
  alongside `:kill`/`:investigate`; and, conditionally, a `SimpleCheck`-based
  policy on `:withdraw` (rule 7's own conditional extension) if that action
  already exists when this bead is implemented (qss.21 landed first) — grep
  for it, don't assume either way.
- A new `Ash.Policy.SimpleCheck` module for `:withdraw`'s "only as yourself"
  check (rule 7's conditional extension), conditional on the same thing —
  qss.21's own spec names it there; this bead does not invent a second one.
- `lib/werewolf_ash/games/action/changes/apply_kill.ex:43-59` —
  `authorize?: false` on `protected?/2`'s `Games.list_actions!` call, in
  place of the forwarded `opts` (rule 8's forced consequence of narrowing
  `:protect`); its other calls in the same function are unchanged.
- `lib/werewolf_ash/games/reactors/resolve_lynch.ex` — **no production
  change**: qss.5 merged this file with `authorize?: false` already on its
  vote-tallying read, and its `[:actor, :target]` load already inherits the
  same flag (settled fact now, not a conditional — see rule 8's own entry
  and its `deps/ash` citations). Left here only so the coder knows to
  re-verify it rather than assume either this spec or the file is wrong.
- `lib/werewolf_ash/games/message.ex` — `policies do` for rules 10-11 (needs
  `authorizers: [Ash.Policy.Authorizer]` added too; it isn't there yet).
- `lib/werewolf_ash/games/reactors/check_win.ex` — `authorize?: false` on the
  `read :living_players` step (rule 4's forced consequence).
- `lib/werewolf_ash/games/game/changes/deal_roles.ex:28` — `authorize?: false`
  on its `list_players!` call (rule 4's other forced consequence, rewritten
  this revision — verify the failure mode against rule 4 itself, not the
  previous revision's description); its `update_player` call two lines
  later already forwards `opts` and is unchanged.
- `lib/werewolf_ash/games/player/validations/user_has_name.ex`,
  `lib/werewolf_ash/games/action/validations/actor_alive.ex`,
  `actor_and_target_in_game.ex`, `no_consecutive_protect.ex`,
  `shoot_requires_pending_hunter.ex`, `target_alive.ex`,
  `type_requires_phase_and_role.ex` (qss.4/qss.18's `Action` validations),
  `lib/werewolf_ash/games/game/validations/max_players_not_below_seated.ex`,
  `minimum_players.ex`, `role_composition_fits.ex` and
  `lib/werewolf_ash/games/player/validations/game_not_full.ex` (qss.14's and
  qss.3's `Game`/`Player` validations) — **no change to any of them**;
  every one already reads with `authorize?: false` (re-checked this round,
  file by file — see "Existing tests this will break"). Listed here only so
  the coder doesn't have to rediscover this by re-reading every file.
- `lib/werewolf_ash/accounts/user.ex` — rules 13/15/17: the narrow
  shared-game grant (rule 17) plus `:email`'s field policy, and a
  `has_many :players, WerewolfAsh.Games.Player` relationship to express it.
  Converting the three existing action-scoped `policy` blocks to `bypass`
  blocks is one way to make rule 13's deny explicit without a test-only fix,
  but a test alone also satisfies the rule (see rule 13's own wording).
- Multi-hop identity checks: `Message.author`/`Action.actor` point at
  `Player`, not `User` — unlike `Game.owner`, which points straight at
  `User` and can use a single-atom `relates_to_actor_via(:owner)`, rules
  7/11's checks need the two-hop path through `Player.user_id` (e.g.
  `relates_to_actor_via([:author, :user])`/`relating_to_actor([:actor,
  :user])`, or an `expr(exists(...))` in the same shape as
  `Message.Visibility.visible_to/1`). Confirm which built-in check (or plain
  `expr`) resolves this statically for a `:create` action before picking one.
- `test/support/generators.ex`, and every existing test file listed under
  "Existing tests this will break" — in particular
  `test/werewolf_ash/games_test.exs` (touched across nearly every describe
  block, including its new "day vote resolution," "update_game_settings"
  and "end to end: owner-configured role composition" blocks) and
  `test/werewolf_ash/games/action_test.exs` (the most work of any file: a
  data-shape addition exposing each seated player's own `User`, including
  the ad-hoc `outsider`/`outsider_wolf`/`other_wolf` players qss.18/qss.20
  added, so every `create_action`/`create_kill_action` call can pass a
  real, correct `actor:`), plus
  `test/werewolf_ash/games/reactors/resolve_lynch_test.exs` and
  `test/werewolf_ash/games/game/changes/resolve_day_vote_test.exs` (qss.5's
  own new test files, neither previously covered by this spec).
- New test files/modules for the policies themselves — one per resource
  reads naturally (e.g. `test/werewolf_ash/games/game/policy_test.exs`,
  `.../player/policy_test.exs`, `.../action/policy_test.exs`,
  `.../message/policy_test.exs`), plus the token-revocation addition in
  `test/werewolf_ash_web/graphql/auth_test.exs` and rule 17's grant test in
  `test/werewolf_ash/accounts/user_test.exs` (27w.9's file, already exists).
