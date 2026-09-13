# werewolf_ash-27w.2: Policies on Games resources

Depends on: none

## For the owner

**What changes.** Players will only see the games, rosters, and messages they actually have a seat in — a game you're not part of won't show up at all. While a game is in progress and a player is still alive: they see their own role; werewolves also see each other's roles and the pack's kill; the seer sees their own investigation results; the bodyguard sees their own protection; no other role or action detail leaks out. Once a player dies, they become a spectator for the rest of that game and can see everything in it — every role, every kill, investigation, protection, and shot — though they still cannot vote, act, or post. Once a game ends, every role is revealed to everyone who played it. Only the game's owner can start it, and every vote, kill, investigation, protection, shot, or chat message a player sends must be sent as themselves, never on someone else's behalf.

**Decisions.**
1. **Decided:** a bodyguard's protection is visible only to the bodyguard who chose it, the same as the wolf kill and the seer's investigation — this closes off telling the wolves whom to avoid once protection can change during the day. Hunter shots stay visible to everyone, the same as votes.
2. **Decided (now just one case of decision 6, below):** a dead werewolf keeps seeing fellow wolves' roles and the pack's kill — nothing in the design narrows it to living wolves only, and it's no longer even a wolf-specific rule: see decision 6.
3. **Decided:** once a game reaches `:finished`, every player's role becomes visible to every seat in that game — built here, not left to the separate follow-up bead that was going to own it.
4. **Decided:** seating another user into a game (useful today for testing/setup) stays open for now; tightening it belongs to the upcoming public sign-up feature.
5. **Decided:** a player can see a fellow player's display name, not their email, in a shared game — this is what lets the roster show names instead of blanks.
6. **Decided:** a dead player is a spectator in an afterlife for the rest of that game — once your own seat has died, you see everything in it: every role, every kill, investigation and protection, not just your own team's. You still cannot vote, act, or post once dead (unchanged).

**Rule changes.** Add to the settled decisions: "a player may read a game, its roster, and its messages only while seated in it (any role, dead or alive); a player sees only their own role, except werewolves also see each other's, and once a game reaches `:finished` every role is visible to every seat (qss.19 adds the dawn reveal of dead players' roles); the night's kill is visible to werewolves only, an investigation result only to the seer who made it, and a protection only to the bodyguard who chose it; a dead player is a spectator for the rest of that game and sees everything in it regardless of the rules above, though they still cannot vote, act, or post; only the game's owner may start it; every vote, kill, investigation, protection, shot, or chat message must be submitted as the sender's own seat, never on another player's behalf."

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
   qss.3's `:start` (rule 3) and one explicit policy for `:join` (rule 6),
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

## Goal

Every Games resource (`Game`, `Player`, `Action`, `Message`) carries real Ash
policies instead of being wide open to any caller that reaches the domain:
players can only read games and rosters they belong to, only their own role
(or a fellow werewolf's), only wolf-vote and their-own-investigate action
detail under the extra rules the game requires, only the owner can start a
game, and every write that identifies "who did this" (`send_message`,
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
3. `Game`'s `:start` action gains a policy —
   `authorize_if relates_to_actor_via(:owner)` or an equivalent expression —
   layered on top of qss.3's `Game.Validations.ActorIsOwner` validation
   *without changing that validation*. A non-owner or anonymous actor is now
   forbidden by the policy; an owner actor sees the same `start` behavior as
   before this bead (qss.3's validation was already satisfied by the same
   condition, so nothing about a correctly-called `start` changes). Because
   `owner_id` is already present on the loaded `Game` struct `start` is
   called with, the policy resolves statically and runs *before* qss.3's
   validation gets a chance to — so the non-owner/anonymous failure mode
   changes class, from qss.3's `Ash.Error.Invalid{errors: [%InvalidAttribute{
   field: :owner_id}]}` to `Ash.Error.Forbidden{errors: [%Ash.Error.Forbidden.Policy{}]}`.
   This is a real, intentional change to `start`'s negative-case contract,
   not a side effect to work around — see the fix to games_test.exs's
   "requires the owner as actor..." test below.
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
   (`lib/werewolf_ash/games/game/changes/deal_roles.ex:27`) calls
   `Games.list_players!(query: [filter: [game_id: game.id]])` with no
   `opts` at all — unlike its own sibling call two lines later (`:33`,
   `Games.update_player(player, %{role: role}, opts)`), which already
   forwards the `opts` `deal/2` was given and must stay exactly as it is.
   Once this rule exists, line 27 needs `authorize?: false` added directly
   (not `opts` forwarded) — this is a game rule fetching the roster it is
   about to deal from, not an access check, the same reasoning
   `AuthorMayPost.load_author/1` already uses, and it matches
   `Game.Validations.MinimumPlayers`'s identical `authorize?: false` on the
   same query one file over (`minimum_players.ex:16`). Forwarding `opts`
   instead would be the wrong fix here: `deal/2` must find every seated
   player regardless of whether the actor who called `start` happens to
   still be one of them. Without this fix, `start` deals zero players to
   anyone, silently, in production — not just in tests.
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
   working, including with no actor at all — no existing test needs any
   change for this rule, since staying open preserves today's behavior
   exactly.
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
   `deal_roles.ex:27`'s own fix under rule 4). Its sibling calls in the same
   function are unaffected and keep forwarding `opts` unchanged: `Phase`
   carries no policy at all (Out of scope), so `Games.get_phase`/
   `Games.list_phases!`'s behavior does not depend on actor either way; and
   `Games.get_player`, `Games.update_player` and `Games.update_action` are
   the kill's own effect, correctly attributed to the werewolf who caused
   it, not a read this rule governs.

   **Conditional forced consequence, added 2026-09-13 per the qss.5 spec
   review:** qss.5 (day-vote resolution; spec PR #9, not merged as of this
   revision, and not a dependency of this bead in either direction) adds
   `lib/werewolf_ash/games/reactors/resolve_lynch.ex`, which reads a day
   phase's `:vote` `Action` rows with no actor to tally the lynch. `:vote`
   gets no type-specific narrowing (above), but it still sits behind rule
   8's own opening baseline — an actor must hold a seat in the row's game at
   all — so a `nil` actor is filtered to `[]` exactly like every other
   unauthenticated `Action` read in this spec, the same failure shape as
   `check_win.ex`'s and `deal_roles.ex`'s reads (rule 4) and `apply_kill.ex`'s
   (above): lynch resolution would silently count zero votes once `Action`
   gains its authorizer, not just in a test. This spec cannot pin the exact
   line or verify the fix is already in place — `resolve_lynch.ex` does not
   exist on `main` as of this revision, so there is nothing here to grep.
   Whichever of 27w.2 and qss.5 is implemented **second** must handle it,
   the same "second bead reconciles" shape this spec already uses for
   qss.14's `:update_settings` (NOTES): if `resolve_lynch.ex` already exists
   when this bead is implemented, grep it for its vote-tallying read and add
   `authorize?: false` there directly if it is missing; if this bead lands
   first, qss.5's own spec and its coder are responsible for adding
   `authorize?: false` to that read when `resolve_lynch.ex` is written,
   citing this rule as the reason. Do not skip the grep on the assumption
   that qss.5's spec already accounts for it — verify against the actual
   file at whichever point it exists.
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
  `Game.Validations.ActorIsOwner` itself. This bead only adds the extra
  `:start` policy (rule 3) and the explicit open policy on `:join` (rule 6)
  on top of qss.3's work, and otherwise treats qss.3's Player/Game shape as
  a given (see Assumption 1).
- 27w.9's `:name` attribute itself, its own set-your-own-name mutation/
  policy, and its nameless-user-cannot-create/join-a-game validation. This
  bead only supplies the read grant (rule 17) that makes a name — once
  27w.9 adds one — visible to a fellow player; everything else about display
  names is 27w.9's (see Assumption 9).
- qss.4's `Action` validations (role, aliveness, phase, one action per
  phase). Rules 7-8 are purely about *who* may create/read an `Action` row,
  never about whether its contents make sense as a game move.
- qss.14's owner-configurable game settings, and any restriction on
  `update_game`/`destroy_game` to the owner — left open per rule 2/
  Assumption 5.
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
- `WerewolfAsh.Games.start_game/1,2,3` — direct tests: the owner actor
  starts the game exactly as before this bead; a non-owner actor and an
  anonymous actor are forbidden with `Ash.Error.Forbidden{errors: [%Ash.Error.Forbidden.Policy{}]}`
  (not qss.3's `ActorIsOwner`-validation `Ash.Error.Invalid`), independent
  of a well-formed, >= 5-player lobby.
- `WerewolfAsh.Games.list_players/0,1`, `WerewolfAsh.Games.get_player/1,2`,
  `WerewolfAsh.Games.list_living_players/1` — direct tests: a fellow game
  member reads a `Player` row (living or dead, via any of the three); a
  user with no seat in that game cannot. `WerewolfAsh.Games.join_game/2,3`
  is unaffected by this bead (rule 6 keeps `:join` open) — a direct test
  that a user with no prior seat can still join a lobby game by its
  join_code with no actor, exactly as qss.3 left it.
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
`AdvancePhase`, `Clock` — this last pair already uses `authorize?: false`
throughout and needs nothing extra); they thread `authorize?: false` through
call sites exercising a *different* contract than the new policies, exactly
as `games_test.exs:27` already does for loading a `Game`'s `owner`. The
genuine production fixes are `check_win.ex`'s read step and
`deal_roles.ex`'s `list_players!` call (both per rule 4), and
`apply_kill.ex`'s `protected?/2` read (per rule 8) — plus, conditionally,
`resolve_lynch.ex`'s vote read if that file exists by the time this bead is
implemented (qss.5, unmerged as of this revision; see rule 8's own entry).

- `test/support/generators.ex`'s `player/1`: the `after_action` hook
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
- `test/werewolf_ash/games_test.exs`, re-grepped against `main` `034a775`
  (`grep -n "Games\.\(get_game\|list_players\|get_player\|get_phase\|create_action\|start_game\|add_player\|update_player\|join_game\|get_action\)" test/werewolf_ash/games_test.exs`
  — line numbers below are current, not the qss.3-era ones from the previous
  revision; 27w.9 added ~94 lines ahead of and inside this file (the
  "games"/"players"/"join_game" describe blocks each gained nameless-user
  tests) and qss.4 reshaped the `describe "actions"` block, both shifting
  everything after them):
  - line 65, `Games.get_game!(game.id, load: :players).players` — needs
    `authorize?: false` (rule 1); line 67's `is_nil(player.role)` depends on
    this same fix. (Unmoved from the previous revision — the two new
    "nameless owner"/"nameless co-player" tests 27w.9 added come *after*
    this test, at lines 137-174, and touch no gated read.)
  - line 73, the positive-match `Games.get_game_by_join_code!(game.join_code)`
    — needs `authorize?: false` (rule 1); line 74's negative (unknown code)
    assertion is unaffected either way. (Unmoved.)
  - line 238, `Games.get_game!(game.id, load: [:current_phase,
    :last_phase_number])` — needs `authorize?: false` (rule 1). (Was line
    199; shifted +39 by the two new "games" tests above it.)
  - line 348, `Games.get_game!(game.id).state == :day` — needs
    `authorize?: false` (rule 1). (Was line 309; same +39 shift.)
  - lines 356-362, "requires the owner as actor, and leaves every player
    roleless": both negative-case assertions are stale, not just missing a
    fix. Replace
    `assert %Ash.Error.Changes.InvalidAttribute{field: :owner_id} = error`
    (both the no-actor call at 356-357 and the `actor: stranger` call at
    359-362) with
    `assert {:error, %Ash.Error.Forbidden{errors: [%Ash.Error.Forbidden.Policy{}]}} = ...`
    — rule 3's policy now forbids both before qss.3's `ActorIsOwner`
    validation runs (see rule 3). (Was lines 317-323.)
  - line 364, `Games.get_game!(game.id).state == :lobby` (same test) — needs
    `authorize?: false` (rule 1). (Was line 325.)
  - line 366, the `for player <- Games.list_players!(query: [filter:
    [game_id: game.id]])` loop (same test) — needs `authorize?: false`
    (rule 4). (Was line 327.)
  - line 382, `Games.get_game!(game.id).state == :lobby` ("requires at least
    5 seated players") — needs `authorize?: false` (rule 1). (Was line 343.)
  - line 392, `Games.list_players!(query: [filter: [game_id: game.id]])`
    ("deals exactly one role...") — needs `authorize?: false` (rule 4);
    line 396's `Enum.map(& &1.role) |> Enum.frequencies()` on that same
    result also depends on rule 5's field policy, which the same
    `authorize?: false` bypasses along with the resource-level gate. No new
    test needs writing for `deal_roles.ex`'s own forced-consequence fix
    (rule 4): once this line's `authorize?: false` is added so the test can
    see the real roster at all, it still fails if `deal_roles.ex:27` isn't
    separately fixed — and it fails loudly, not silently: that line's
    `list_players!` returns `[]`, and `RoleAssignment.composition/1` is
    guarded `when player_count >= 5`, so `composition(0)` raises
    `FunctionClauseError` inside the `after_action` hook. This test is
    already the pin; a coder who applies this fix mechanically without also
    fixing `deal_roles.ex:27` gets an immediate crash here. **Do not
    "fix" that crash by loosening `composition/1`'s guard** — the guard is
    correct (qss.3 defines its contract only for 5 or more players, and
    rule 9 of qss.3 blocks any smaller start); the empty roster is the bug.
    (Was line 353.)
  - line 419, `Games.list_players!(query: [filter: [game_id:
    game.id]]) |> length() == 2` ("adds and removes players one at a time")
    — needs `authorize?: false` (rule 4). (Missed in the previous revision:
    this test is distinct from "a seat cannot be given up..." below, whose
    `list_players!`/`get_player!` calls *were* already listed.)
  - line 416, `assert is_nil(player.role)` off `player =
    Games.add_player!(game.id, alice.id)` (same test) — needs
    `authorize?: false` on the `add_player!` call (rule 5: the field policy
    applies to a single-record create's own result, not just to a later
    read). (Was line 377.)
  - line 423, `Games.list_players!(query: [filter: [game_id: game.id]]) |>
    Enum.map(& &1.user_id) == [game.owner_id]` (same test, after
    `remove_player!`) — needs `authorize?: false` (rule 4). (New to this
    list, same reason as line 419.)
  - line 454, `[player | _] = Games.list_players!(query: ...)` ("a seat
    cannot be given up once the game has left the lobby") — needs
    `authorize?: false` (rule 4). (Was line 415.)
  - line 460, `Games.get_player!(player.id).id` (same test) — needs
    `authorize?: false` (rule 4); `.id` itself is a primary key and always
    field-visible, but the row is invisible at all without this fix. (Was
    line 421.)
  - line 466-467, `player = Games.update_player!(player, %{role: :seer});
    assert player.role == :seer` ("updates role and aliveness") — needs
    `authorize?: false` on that `update_player!` call (rule 5, same
    mechanism as line 416). (Was line 428.)
  - line 479, `Games.list_players!(query: [filter: [game_id: game.id]]) ==
    []` ("are deleted along with their game") — **no change**: `game` was
    just destroyed and its players cascade-deleted, so this is genuinely
    empty, the same shape as a policy-filtered empty result.
  - Lines 482-506 (27w.9's three new tests: "refuses to seat a nameless
    user...", "seats a named user...", "two players may share..."): **no
    change** — the two "refuses" tests' follow-up `list_players!`
    (lines 489, 529) are genuinely empty (`UserHasName` rejected the seat
    before any row was created), and the other two only read `.user_id`/
    `.id` off `add_player!`/`join_game!` results, neither of which rule 5
    governs.
  - line 518, `assert is_nil(player.role)` off `player =
    Games.join_game!(game.join_code, user.id)` ("seats a user in the game
    named by its join_code") — needs `authorize?: false` on the
    `join_game!` call (rule 5, same mechanism as line 416/466). (Was line
    453.)
  - line 608, `Games.get_game!(game.id, load: :phases).phases |>
    Enum.map(& &1.id)` ("are numbered per game and listed in order") —
    needs `authorize?: false` (rule 1). (Was line 514; not a new break, the
    describe block just moved.)
  - line 644, `Games.create_action!(ctx.phase.id, ctx.alice.id, ctx.bob.id,
    :vote)` ("records who did what to whom in a phase") — needs
    `authorize?: false` (rule 7).
  - line 652, `Games.get_player!(ctx.alice.id, load: [:performed_actions,
    :targeted_by_actions])` (same test) — needs `authorize?: false` for the
    `Player` read (rule 4) *and* because `:performed_actions`/
    `:targeted_by_actions` are `Action` reads, gated by rule 8.
  - line 657, `Games.get_player!(ctx.bob.id, load: [:targeted_by_actions])`
    (same test) — same fix, same reasons.
  - line 660, `Games.get_phase!(ctx.phase.id, load: :actions).actions` (same
    test) — `Phase` itself carries no policy, but the loaded `:actions`
    relationship is an `Action` read gated by rule 8; needs
    `authorize?: false`.
  - line 664, `Games.create_action!(ctx.phase.id, ctx.alice.id, ctx.bob.id,
    :vote)` ("allows one action per actor, phase and type") — needs
    `authorize?: false` (rule 7).
  - line 666-667, `Games.create_action(ctx.phase.id, ctx.alice.id,
    ctx.alice.id, :vote)` (same test, expects the duplicate-identity error
    qss.4 now reports as `field: :phase_id`) — needs `authorize?: false`
    (rule 7): without it this is forbidden before the identity check ever
    runs, changing the expected error from `Ash.Error.Invalid{errors:
    [%{field: :phase_id}]}` to a policy-forbidden one.
  - line 672-673, `Games.create_action!(ctx.phase.id, ctx.alice.id,
    ctx.bob.id, :protect)` (same test, after qss.4's
    `Games.update_player!(ctx.alice, %{role: :bodyguard})` at line 670,
    which needs no fix — its return is discarded) — needs
    `authorize?: false` (rule 7).
  - line 677, `Games.create_action!(day2.id, ctx.alice.id, ctx.bob.id,
    :vote)` (same test) — needs `authorize?: false` (rule 7).
  - line 682, `Games.create_action(ctx.phase.id, ctx.alice.id, ctx.bob.id,
    :dance)` ("rejects unknown types") — needs `authorize?: false` (rule 7),
    for the same reason as line 666-667: otherwise forbidden pre-empts the
    `:type` validation the test expects.
  - line 686, `Games.create_action!(ctx.phase.id, ctx.alice.id, ctx.bob.id,
    :vote)` ("are deleted along with their phase") — needs
    `authorize?: false` (rule 7).
  - line 689, `Games.get_action(action.id)` (same test) — **no change**: the
    action is genuinely gone (its phase was destroyed), and a
    genuinely-absent row and a policy-filtered-to-empty one raise the same
    error shape.
  - Nothing else in this file changes: every `create_game`/`update_game`/
    `destroy_game`/`end_day`/`end_night`/`create_phase`/`update_phase`/
    `remove_player!`/`update_action!`/the rest of `join_game`/`join_game!`'s
    own describe block call stays as-is (rules 2/6/9) — none of them read a
    field rule 5 governs off their own result, or create an `Action` as
    someone else. The "phase transitions" describe block's `start_game!`
    calls already pass `actor: owner` from qss.3 — this bead's `:start`
    policy checks the identical condition, so an already-fixed call needs no
    further change.
- `test/werewolf_ash/games/action/changes/apply_kill_test.exs` — new since
  the previous revision (qss.4); not previously audited
  (`grep -n "Games\." test/werewolf_ash/games/action/changes/apply_kill_test.exs`):
  - lines 38, 54 and 66, `Games.get_player!(target.id).alive` (three tests
    under `describe "change/3"`) — need `authorize?: false` (rule 4; `.alive`
    carries no field policy, so rule 5 does not additionally apply here).
  - line 49, `Games.create_action!(day.id, bodyguard.id, target.id,
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
  - The other four new qss.4 test files under `test/werewolf_ash/games/action/`
    (`actor_alive_test.exs`, `type_requires_phase_and_role_test.exs`,
    `shoot_requires_pending_hunter_test.exs`,
    `changes/record_investigation_result_test.exs`) need **no change**:
    checked by grep for any `Games.` call
    (`grep -n "Games\." test/werewolf_ash/games/action/validations/*.exs test/werewolf_ash/games/action/changes/record_investigation_result_test.exs`)
    — the only hits are `Games.update_player!(actor_or_hunter, %{alive:
    false})` calls whose return is discarded, and none of them create or
    read an `Action` through the domain interface (they call the validation/
    change modules directly on bare changesets/structs, the same pattern as
    `AuthorMayPost`'s own tests).

**No forced consequence found in `Player.Validations.UserHasName`.** This is
qss.4/27w.9's new `Player`-seating validation (`lib/werewolf_ash/games/player/validations/user_has_name.ex`),
the same shape of risk as `CheckWin`'s and `deal_roles.ex`'s reads (an
actor-less lookup of a resource this bead adds a policy to) — checked per
this round's request. It already reads with `Ash.get(User, user_id,
authorize?: false)` (line 28), and its own moduledoc says why: "The user is
looked up without authorization: this is a game rule, not an access check...
the same convention `Message.Validations.AuthorMayPost` uses." No production
fix is needed here, and no new test needs writing — both existing test files
already pass regardless of this bead: `user_has_name_test.exs` calls
`UserHasName.validate/3` directly on a manually-built changeset (never
through an authorized action, so `User`'s new policies never run), and
`games_test.exs`'s "refuses to seat a nameless user"/"seats a named user"
tests (lines 482-497, 521-538, listed above) call `Player`'s `:create`/`:join`
with no actor and pass regardless, since `UserHasName`'s own `Ash.get/3`
already bypasses authorization.

**`test/werewolf_ash/games/action_test.exs` — missing from every previous
revision of this spec.** 356 lines, all new with qss.4, exercising
`create_action`/`create_kill_action` end to end through the domain interface
with no actor anywhere
(`grep -n "Games\." test/werewolf_ash/games/action_test.exs` — full output
below, 76 hits):

```
22:    game = Games.start_game!(game, %{now: @start}, actor: owner)
25:      Games.list_players!(query: [filter: [game_id: game.id]])
32:    Games.get_game!(game.id, load: :current_phase).current_phase
50:      action = Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote)
53:      assert Games.get_action!(action.id).id == action.id
55:      assert Games.list_actions!(query: [filter: [phase_id: day.id]])
63:      game = Games.end_day!(game, %{now: @dusk})
66:      action = Games.create_action!(night.id, p.seer.id, p.werewolf.id, :investigate)
74:      action = Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect)
80:      Games.update_player!(p.hunter, %{alive: false})
84:      action = Games.create_action!(day.id, p.hunter.id, p.villager.id, :shoot)
94:      night_game = Games.end_day!(game, %{now: @dusk})
97:      Games.update_player!(p.villager, %{alive: false})
98:      Games.update_player!(p.seer, %{alive: false})
99:      Games.update_player!(p.bodyguard, %{alive: false})
102:               Games.create_action(day.id, p.villager.id, p.werewolf.id, :vote)
105:               Games.create_action(night.id, p.seer.id, p.werewolf.id, :investigate)
108:               Games.create_action(day.id, p.bodyguard.id, p.villager.id, :protect)
110:      assert Games.list_actions!(query: [filter: [phase_id: day.id]]) == []
111:      assert Games.list_actions!(query: [filter: [phase_id: night.id]]) == []
115:      game = Games.end_day!(game, %{now: @dusk})
119:               Games.create_action(night.id, p.villager.id, p.werewolf.id, :vote)
121:      assert Games.list_actions!(query: [filter: [phase_id: night.id]]) == []
129:      night = current_phase(Games.end_day!(game, %{now: @dusk}))
132:               Games.create_action(day.id, p.seer.id, p.werewolf.id, :investigate)
135:               Games.create_action(night.id, p.villager.id, p.werewolf.id, :investigate)
143:      night = current_phase(Games.end_day!(game, %{now: @dusk}))
146:               Games.create_action(night.id, p.bodyguard.id, p.villager.id, :protect)
149:               Games.create_action(day.id, p.villager.id, p.werewolf.id, :protect)
156:               Games.create_action(day.id, p.bodyguard.id, p.bodyguard.id, :protect)
164:               Games.create_action(day.id, p.villager.id, p.werewolf.id, :shoot)
172:      first = Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote)
175:               Games.create_action(day.id, p.villager.id, p.bodyguard.id, :vote)
177:      unchanged = Games.get_action!(first.id)
185:      Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote)
188:               Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect)
190:      game = Games.end_day!(game, %{now: @dusk})
191:      game = Games.end_night!(game, %{now: @dawn})
194:      assert %{type: :vote} = Games.create_action!(day2.id, p.villager.id, p.werewolf.id, :vote)
201:               Games.create_action(day.id, p.werewolf.id, p.villager.id, :kill)
209:      game = Games.end_day!(game, %{now: @dusk})
215:      action = Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id)
219:      assert Games.get_player!(p.villager.id).alive == false
228:               Games.create_kill_action(night.id, p.villager.id, p.bodyguard.id)
231:               Games.create_kill_action(day.id, p.werewolf.id, p.villager.id)
233:      Games.update_player!(p.werewolf, %{alive: false})
236:               Games.create_kill_action(night.id, p.werewolf.id, p.villager.id)
238:      assert Games.list_actions!(query: [filter: [phase_id: night.id]]) == []
246:      Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect)
248:      action = Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id)
251:      assert Games.get_player!(p.villager.id).alive == true
259:      first = Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id)
263:               Games.create_kill_action(night.id, other_wolf.id, p.bodyguard.id)
266:               Games.create_kill_action(night.id, p.werewolf.id, p.bodyguard.id)
268:      assert Games.get_action!(first.id).id == first.id
269:      assert Games.get_player!(p.villager.id).alive == false
270:      assert Games.get_player!(p.bodyguard.id).alive == true
278:      Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id)
297:      Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect)
298:      Games.create_action!(day.id, p.villager.id, p.werewolf.id, :vote)
300:      game = Games.end_day!(game, %{now: @dusk})
304:               Games.create_action(night.id, p.villager.id, p.werewolf.id, :vote)
307:      kill = Games.create_kill_action!(night.id, p.werewolf.id, target.id)
310:      assert Games.get_player!(target.id).alive == false
312:      seer_action = Games.create_action!(night.id, p.seer.id, p.werewolf.id, :investigate)
316:               Games.create_kill_action(night.id, p.villager.id, p.bodyguard.id)
319:               Games.create_kill_action(night.id, p.werewolf.id, p.bodyguard.id)
321:      assert Games.get_player!(target.id).alive == false
323:      assert Games.list_actions!(query: [filter: [phase_id: night.id, type: :kill]])
331:      Games.create_action!(day.id, p.bodyguard.id, p.villager.id, :protect)
333:      game = Games.end_day!(game, %{now: @dusk})
336:      kill = Games.create_kill_action!(night.id, p.werewolf.id, p.villager.id)
339:      assert Games.get_player!(p.villager.id).alive == true
345:      Games.update_player!(p.hunter, %{alive: false})
349:      shot = Games.create_action!(day.id, p.hunter.id, p.villager.id, :shoot)
353:               Games.create_action(day.id, p.villager.id, p.werewolf.id, :shoot)
```

Three groups need a fix, one needs none:

1. **No fix**: `end_day!`/`end_night!` (63, 94, 115, 129, 143, 190, 191, 209,
   300, 333) — `Game`'s `:end_day`/`:end_night` stay open (rule 2).
   `update_player!` (80, 97, 98, 99, 233, 345) — `Player`'s `:update` stays
   open (rule 6) and none of these six read `.role`/any field-policy-governed
   value off the return, so rule 5 does not reach them either. Line 22's
   `start_game!` already carries `actor: owner`.

2. **`started_game/0` and `current_phase/1`, the file's two setup helpers —
   `authorize?: false`, not a real actor.** Neither represents a player
   acting; both are bookkeeping reads verifying/fetching state, the same
   role `deal_roles.ex`'s and `minimum_players.ex`'s internal reads play (and
   the same reasoning: they must find the real roster/phase regardless of
   who, if anyone, is asking).
   - line 25, `started_game/0`'s `Games.list_players!(...)` — needs
     `authorize?: false` (rules 4 *and* 5: line 26's `Map.new(&{&1.role,
     &1})`, not shown in the grep above, reads `.role` off this same
     result). This is the single most consequential fix in this file: left
     unfixed, `p` is `%{}` and every test in the file that destructures
     `p.villager`/`p.werewolf`/etc. raises `KeyError`.
   - line 32, `current_phase/1`'s `Games.get_game!(game.id, load:
     :current_phase).current_phase` — needs `authorize?: false` (rule 1);
     one fix here covers every call site that goes through this helper
     (including the two at 129 and 143 that wrap it around `end_day!`'s
     result inline).

3. **Every `create_action`/`create_kill_action` call — `actor:`, the
   submitting player's own `User`, not `authorize?: false`.** This is the
   opposite choice from group 2, deliberately: these calls *are* the game
   actions this bead's rule 7 governs, and every single one in this file
   already submits as the correct player for what it is testing — none of
   qss.4's own role/phase/aliveness/uniqueness tests are testing
   impersonation, so the player named as the second positional argument
   (`p.villager.id`, `p.seer.id`, `p.werewolf.id`, ..., or `other_wolf.id`
   at line 263) is always the one whose `User` `actor:` must carry. Using
   `authorize?: false` here instead would make every one of these tests
   pass regardless of rule 7, which is not what a "policy tests as
   different actors" bead should ship. This needs a data-shape addition to
   the file's fixtures — `started_game/0` (and the inline
   `generate(player(game_id: game.id, role: :werewolf))` calls making
   `other_wolf` at lines 260/279) must expose each player's own `User`
   alongside the `Player` it already tracks, e.g. by resolving
   `player.user_id` via `Ash.get!(WerewolfAsh.Accounts.User, player.user_id,
   authorize?: false)` per player and passing that as `actor:`. Every line:
   50, 66, 74, 84, 102, 105, 108, 119, 132, 135, 146, 149, 156, 164, 172,
   175, 185, 188, 194, 201, 215, 228, 231, 236, 246, 248, 259, 263, 266,
   278, 297, 298, 304, 307, 312, 316, 319, 331, 336, 349, 353.

4. **Every remaining read verifying state after the fact —
   `authorize?: false`, same reasoning as group 2.** These don't represent
   anyone "checking" in the game's own terms; they're the test confirming
   what got written. `get_action!` (53, 177, 268), `list_actions!` (55, 110,
   111, 121, 238, 323), `get_player!` (219, 251, 269, 270, 310, 321, 339) —
   all need `authorize?: false`.

`Ash.Seed.seed!` (lines 282-288, "the database refuses a second kill row
even bypassing the application") needs no change: seeding writes straight to
the data layer, bypassing Ash actions and policies entirely, which is the
point of that test.

Correction to the previous revision: the claim that `git diff e3de03d..034a775
--stat` showed only three test files changed was false — that command was
run scoped to an explicit list of paths (the files already in this section),
so it could only ever confirm or deny changes to *those* files; it could not
and did not show whether other files existed. Run unscoped, over all of
`test/`, it lists 11 files:

```
$ git diff --stat e3de03d..034a775 -- test/
 test/support/generators.ex                         |  22 +-
 test/werewolf_ash/accounts/user_test.exs           |  67 ++++
 .../games/action/changes/apply_kill_test.exs       |  69 ++++
 .../changes/record_investigation_result_test.exs   |  54 ++++
 .../games/action/validations/actor_alive_test.exs  |  38 +++
 .../shoot_requires_pending_hunter_test.exs         |  61 ++++
 .../type_requires_phase_and_role_test.exs          |  90 ++++++
 test/werewolf_ash/games/action_test.exs            | 356 +++++++++++++++++++++
 .../player/validations/user_has_name_test.exs      |  37 +++
 test/werewolf_ash/games_test.exs                   | 102 +++++-
 test/werewolf_ash_web/graphql/auth_test.exs        | 160 +++++++++
 11 files changed, 1052 insertions(+), 4 deletions(-)
```

`test/werewolf_ash/games/action_test.exs` (356 lines, all-new, qss.4) was
missing from every previous revision of this spec — see its own entry below.
The other 9 files in this list (`generators.ex`, `user_test.exs`,
`apply_kill_test.exs`, `record_investigation_result_test.exs`,
`actor_alive_test.exs`, `shoot_requires_pending_hunter_test.exs`,
`type_requires_phase_and_role_test.exs`, `user_has_name_test.exs`,
`games_test.exs`, `auth_test.exs`) are already accounted for above. Every
file *not* in this list — `deal_roles_test.exs`, `check_win_test.exs`,
`resolve_win_test.exs`, `message_test.exs`, `visibility_test.exs`,
`preparations/visible_to_test.exs`, `author_may_post_test.exs` — is
confirmed unchanged since the previous revision by the same diff, and by
re-running each file's own grep below against `034a775`; every line number
in that cluster is unchanged.

- `test/werewolf_ash/games/game/changes/deal_roles_test.exs`
  (`grep -n "Games\.\(list_players\|get_player\)" test/werewolf_ash/games/game/changes/deal_roles_test.exs`
  → 23, 35, 43; both tests):
  - line 23, `Games.list_players!(query: [filter: [game_id: game.id]])`
    (feeding line 27's `.role` frequencies) — needs `authorize?: false`
    (rules 4 and 5). This is the other existing pin for `deal_roles.ex:27`'s
    own forced-consequence fix (see the games_test.exs note above): fix
    this line alone and the test calls `DealRoles.change/3`'s `after_action`
    hook directly, so it fails the same way if `deal_roles.ex:27` isn't also
    fixed — a `FunctionClauseError` from `composition(0)`, per the
    games_test.exs note above. The guard is not the bug; the empty roster is.
  - line 35, `Games.list_players!(query: [filter: [game_id: other_game.id]])`
    — needs `authorize?: false` (rule 4).
  - line 43, `Games.get_player!(other_player.id).role` — needs
    `authorize?: false` (rules 4 and 5).
- `test/werewolf_ash/games/reactors/check_win_test.exs`
  (`grep -n "Games\.get_game!" test/werewolf_ash/games/reactors/check_win_test.exs`
  → line 106 only): "never touches the game"'s `Games.get_game!(game.id)`
  needs `authorize?: false` (rule 1). `check_win.ex`'s own
  `read :living_players` step fix is rule 4's forced consequence, not a
  separate item — see rule 4.
- `test/werewolf_ash/games/reactors/resolve_win_test.exs`
  (`grep -n "Games\.\(get_game\|list_players\|start_game\)" test/werewolf_ash/games/reactors/resolve_win_test.exs`
  → 18, 20, 33, 44, 53, 62, 73):
  - line 33, `Games.get_game!(game.id)` ("leaves a game alone...") — needs
    `authorize?: false` (rule 1).
  - line 44, `Games.list_players!(...) |> Enum.find(&(&1.role ==
    :werewolf))` ("finishes the game for the village") — needs
    `authorize?: false` (rules 4 and 5).
  - line 53, `Games.get_game!(game.id).winner` (same test) — needs
    `authorize?: false` (rule 1).
  - line 62, `Games.list_players!(...) |> Enum.split_with(&(&1.role ==
    :werewolf))` ("finishes the game for the wolves") — needs
    `authorize?: false` (rules 4 and 5).
  - line 73, `Games.get_game!(game.id).state` (same test) — needs
    `authorize?: false` (rule 1).
  - line 18 (`load: :owner, authorize?: false`) and the `start/1` helper's
    `Games.start_game!(game, actor: owner)` are already correct; no change.
- `test/werewolf_ash/games/message_test.exs`
  (`grep -n "Games\.\(send_message\|list_messages_visible_to\)" test/werewolf_ash/games/message_test.exs`
  → 34, 38, 43, 88, 91, 149, 150, 154, 162):
  - `post!/1,3` and `post/1,3` (lines 33-38) — add `authorize?: false`
    (rule 11).
  - `visible_ids/1,2` (lines 41-45) — add `authorize?: false` (rule 10).
  - line 88 and line 91, the two direct `Games.send_message(...)` calls in
    "the author must be a player of the game" (outside the `post`/`post!`
    helpers) — need `authorize?: false` (rule 11), or every actor-less call
    is forbidden before `AuthorMayPost` ever runs, regardless of which
    `author_id` was passed.
  - line 149 and line 150, the two direct `Games.list_messages_visible_to!`
    calls in "messages never cross games..." — need `authorize?: false`
    (rule 10).
  - line 154, `Games.list_messages_visible_to!(ctx.dead_wolf.id)` ("messages
    come back oldest first") — needs `authorize?: false` (rule 10).
  - line 162, `Games.list_messages_visible_to!(ctx.villager.id, load:
    :author)` ("the author can be loaded") — needs `authorize?: false`
    (rule 10 for the `Message` read, and rule 4 for the loaded `:author`
    `Player`).
  - `messages_in/1`'s `Ash.read!()` (lines 185-188) — needs
    `authorize?: false` (rule 10).
  - `test/werewolf_ash/games/message/validations/author_may_post_test.exs`:
    **no change** — it exercises `check/3`/`validate/3` on bare structs and
    a manually-built changeset, never through an authorized action.
- `test/werewolf_ash/games/message/visibility_test.exs`
  (`grep -n "Games\.send_message\|Ash\.read!" test/werewolf_ash/games/message/visibility_test.exs`
  → 24, 25, 39): the `setup` block's two `Games.send_message!` calls (lines
  24-25) need `authorize?: false` (rule 11); `visible_message_ids/1`'s
  `Ash.read!()` (line 39) needs it too (rule 10).
- `test/werewolf_ash/games/message/preparations/visible_to_test.exs`
  (`grep -n "Games\.send_message\|Ash\.read!" test/werewolf_ash/games/message/preparations/visible_to_test.exs`
  → 18, 31, 36): the `setup` block's `Games.send_message!` call (line 18)
  needs `authorize?: false` (rule 11); the two `Ash.read!()` calls in the
  test bodies (lines 31 and 36) need it too (rule 10) — `prepared_query/1`
  only builds the query, the read happens at the call site.
- `test/werewolf_ash_web/graphql/auth_test.exs` — grown substantially (27w.9
  added `describe "setName / currentUser.name"`, 27w.8 added the
  `SendMagicLinkEmail`/`magic_link_url` email-delivery tests and the
  `FailingMailerAdapter`), re-read in full against `034a775`. Correction to
  the previous revision's "no existing test needs a fix": that was wrong —
  two existing tests need no *test-code* change, but only pass because rule
  17's `:email` field policy is written correctly (see rule 17's own
  `AshAuthenticationInteraction`/`action(:sign_in_with_magic_link)` grants);
  written the naive way (`id == actor(:id)` alone), both break for real, not
  hypothetically:
  - lines 110-111, `"result" => %{"id" => id, "email" => ^email}` inside
    "request -> sign in -> authenticated currentUser, registering a new user
    on first use" — needs the `action(:sign_in_with_magic_link)` grant, or
    `email` renders as forbidden/`nil` and the pattern match fails.
  - lines 154-171, "requestMagicLink succeeds identically for an
    unregistered email as for a registered one" — the second
    `requestMagicLink` call at line 165 requests a link for
    `registered_email`, which by then *is* registered (signed in at line
    157), landing in `Request.run/3`'s `{:ok, user}` branch
    (`sender.send(user, ...)`); needs the `AshAuthenticationInteraction`
    grant, or `SendMagicLinkEmail.send/3` raises trying `to_string/1` on a
    forbidden `:email`.
  The four `setName`/`currentUser.name` tests all sign in a real user first
  (`sign_in/1`) and act as that same actor throughout, so `:set_name`'s and
  `:current_user`'s own pre-existing policies (both `id == actor(:id)`,
  unaffected by this bead) already cover them; the one anonymous case ("a
  call with no bearer token...") already expects an `errors` entry, which it
  gets regardless of reason (`:current_user` resolving no record for
  `read_action`, unrelated to rule 13/17). Every other
  `SendMagicLinkEmail`/`magic_link_url` test calls those modules' functions
  directly on bare structs/strings, never through an authorized action. Add
  the new token-revocation test here (rule 14).

## Touches

Advisory only.

- `lib/werewolf_ash/games/game.ex` — `authorizers: [Ash.Policy.Authorizer]`,
  a `policies do` block for rules 1-3.
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
- `lib/werewolf_ash/games/reactors/resolve_lynch.ex` — conditional, not a
  file this bead creates: if it already exists when this bead is
  implemented (qss.5 landed first), its vote-tallying read needs
  `authorize?: false` too (rule 8's second forced consequence); grep for it
  at that time, don't assume it's missing or already fixed.
- `lib/werewolf_ash/games/message.ex` — `policies do` for rules 10-11 (needs
  `authorizers: [Ash.Policy.Authorizer]` added too; it isn't there yet).
- `lib/werewolf_ash/games/reactors/check_win.ex` — `authorize?: false` on the
  `read :living_players` step (rule 4's forced consequence).
- `lib/werewolf_ash/games/game/changes/deal_roles.ex:27` — `authorize?: false`
  on its `list_players!` call (rule 4's other forced consequence); its
  `update_player` call two lines later already forwards `opts` and is
  unchanged.
- `lib/werewolf_ash/games/player/validations/user_has_name.ex` — **no
  change**; already uses `authorize?: false` (checked this round, see the
  note under "Existing tests this will break").
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
- `test/support/generators.ex`, and the existing test files listed under
  "Existing tests this will break" — `test/werewolf_ash/games/action_test.exs`
  needs the most work of these: a data-shape addition exposing each seated
  player's own `User` (see that file's entry) so its `create_action`/
  `create_kill_action` calls can pass a real, correct `actor:`.
- New test files/modules for the policies themselves — one per resource
  reads naturally (e.g. `test/werewolf_ash/games/game/policy_test.exs`,
  `.../player/policy_test.exs`, `.../action/policy_test.exs`,
  `.../message/policy_test.exs`), plus the token-revocation addition in
  `test/werewolf_ash_web/graphql/auth_test.exs` and rule 17's grant test in
  `test/werewolf_ash/accounts/user_test.exs` (27w.9's file, already exists).
