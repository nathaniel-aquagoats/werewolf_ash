# werewolf_ash-27w.3: Expose game queries and mutations in GraphQL

Implemented in PR #29.

Depends on: werewolf_ash-qss.7

## For the owner

**What changes.** A signed-in player can, over GraphQL, create a game (the
server invents the join code), join by code, leave, start, change the lobby
settings, and take every in-game action: vote, withdraw a vote, kill,
investigate, protect, withdraw a protection, shoot. They can list their games
(newest first) and open one to see its players, phases, actions, the vote
tally, the hunter window and their own seat. Nobody ever says who they are:
the server works out the caller's seat and the game's open phase. Other players' roles and night actions stay hidden. So do other
people's votes that no longer count, which tightens today's rule.

**Decisions.**
1. Where does identity come from? — **Decided:** the signed-in user. No
   `actorId`, `userId`, `ownerId` or `phaseId` input anywhere; the server
   resolves the caller's seat and the open phase (2026-09-28).
2. How is the join code made? — **Decided:** server-generated, short, random,
   no look-alike characters, retried on a collision; `createGame` takes no
   `joinCode` (2026-09-28).
3. What extra is in scope? — **Decided:** `updateGameSettings`,
   `withdrawVote`, `withdrawProtection`, `Phase.voteTally`,
   `Game.pendingHunterId` and `Game.hunterDeadlineAt` (2026-09-28).
4. May the owner leave? — **Decided:** no, `leaveGame` is refused for the
   owner (2026-09-28).
5. What does `game(id)` show? — **Decided:** everything the policies allow:
   players (role per the existing field policy), current phase, all phases,
   each phase's actions, and `mySeat` (2026-09-28).
6. What does `myGames` list? — **Decided:** every game the caller is seated
   in (lobby, running, finished), newest first, no pagination (2026-09-28).
7. Hiding `Player.alive` from living readers until dawn? — **Decided:** not
   this bead; it is qss.19 (2026-09-28).
8. Join codes: case-sensitive? — **Decided:** no, case-insensitive
   (2026-09-29). Codes are generated uppercase (6 characters, no look-alike
   characters) and `joinGame` upcases what it is given.
9. Do players see each other's email? — **Decided:** never; display names
   only. `User.email` becomes nullable in the GraphQL schema (2026-09-29).
10. What is "newest first" for `myGames`? — **Decided:** the game's creation
    time, newest first (2026-09-29).
11. Who sees which day votes? — **Decided:** the existing rule that let every
    seated reader see every vote row changes. A living player sees only the
    votes that currently count (living voter, living target) plus their own;
    the dead see all, the same as the vote tally. It applies to every way of
    reading votes, not only the tally (2026-09-29).
12. Which id do `startGame` and `updateGameSettings` take? — **Decided:** the
    game's `id` (AshGraphql's standard update lookup), a departure from the
    literal `startGame(gameId)` of decision 1. Every other mutation takes
    `gameId` (2026-09-29).
13. May a vote or protection be withdrawn at night? — **Decided:** no.
    `withdrawVote` and `withdrawProtection` need the day to be open and are
    refused otherwise, including right after dusk (coordinator, 2026-09-29).
14. Smaller calls made by the author and confirmed as standing coordinator
    decisions: a hidden role comes back `null` with a "forbidden field"
    entry in `errors`; `createGame` takes `name` and optional `timezone`,
    `dayStart`, `dayEnd` (defaults UTC, 08:00, 20:00); internal actions keep
    their open policies because they are not exposed.

**Rule changes.** Add to CLAUDE.md, under Conventions & Patterns:

> GraphQL mutations never take an actor, user, owner or phase id: the server
> derives the caller's seat and the game's open phase from the signed-in user
> and the game id, by calling the existing domain functions as that actor, so
> every existing rule and policy still decides. Only actions written for
> GraphQL are exposed; the internal ones (`end_day`, `end_night`, `finish`,
> `Player :update`, ...) never are.

Change (27w.2 rule 8, the Action read rule; CLAUDE.md's "The dead see
everything" bullet stays true): a `:vote` row is readable by a living seated
reader only while it currently counts (living voter, living target) or is
their own; a dead seated reader reads every vote row.

## Goal

A signed-in player can play a whole game through `/gql` alone. Lobby: create,
join by a server-made code, leave (not the owner), configure, start. Play:
vote, kill, investigate, protect, shoot, and withdraw a vote or protection,
each naming only the game and (where relevant) the target. Reading: `myGames`,
`game(id)` with `mySeat`, the vote tally and the hunter window. Nothing the
Ash policies hide is visible over GraphQL, and no write can be aimed at
another player's seat.

## Rules

Terms: "the caller" is the Ash actor set from the bearer token
(`BearerActor`). "The caller's seat" is the `Player` with that `user_id` in the
named game. "The open phase" is the game's `current_phase` (`ended_at` nil).
All GraphQL names below are the camelCase of the snake_case names.

### Schema wiring

1. `WerewolfAsh.Games` gains `AshGraphql.Domain` and a `graphql` block that
   declares every query and mutation below. `WerewolfAsh.Games` is added to
   the `domains:` list of `WerewolfAshWeb.GraphqlSchema`. `Message` gets no
   `graphql` section and no query or mutation (27w.6 owns it).
2. `Game`, `Player`, `Phase` and `Action` gain `AshGraphql.Resource` with a
   `graphql do type ... end` section (types `:game`, `:player`, `:phase`,
   `:action`). No query or mutation returns a bare `Phase`, and there is no
   root `Player` or `Action` query: `Phase` has no authorizer, so it is
   reachable only through a `Game` the caller may read.
3. No mutation or query input, in the whole generated schema, is named
   `actorId`, `userId`, `ownerId` or `phaseId`, or (in the Games mutations)
   `now`, `pick`, `winner`, `role`, `alive`, `state`, `pendingHunterId` or
   `hunterDeadlineAt`. The schema names no mutation for `end_day`,
   `end_night`, `finish`, `Game :update`/`:destroy`, `Player :create`/
   `:update`/`:destroy`/`:join`, `Action :create`/`:kill`/`:update`/`:destroy`/
   `:withdraw`, `resolve_hunter_deadline` or any `Phase` write.
4. `Phase.summary` is hidden from GraphQL (`hide_fields`): nothing writes it
   yet and `Phase` has no policy of its own to narrow it later.
5. On `User`'s graphql section, `email` is declared nullable
   (`nullable_fields [:email]`). Without it, a fellow player's forbidden
   `email` would null the non-null `Player.user`, then the player, then the
   game. Reading your own `email` (`currentUser`) is unchanged.

### Reads

6. `game(id)` is a `get` query on `Game`'s primary read. A caller with no seat
   in that game, an unknown id, and no token all get `null` with no `errors`
   entry (the Game read policy filters; `allow_nil?` stays at its default
   `true`).
7. `myGames` is a `list` query backed by a new Game read action `:mine`
   (code interface `Games.my_games/1`, with Ash's usual options). It has no
   filter of its own (an action-level `filter expr(... ^actor(:id))` raises
   `ReadActionRequiresActor` with no token,
   `deps/ash/lib/ash/query/query.ex:1618`): only a sort, `inserted_at`
   descending with `id` descending as the tiebreak. The existing
   `action_type(:read)` policy is what narrows it to exactly the games in
   which the caller holds a seat, whatever the state. No pagination
   arguments. With no token it returns `[]`.
8. `Game` exposes, through generated fields and relationships: its public
   attributes (including the qss.14 settings, `state`, `phaseEndsAt`,
   `winner`, and qss.7's `pendingHunterId` and `hunterDeadlineAt`),
   `owner`, `players` (ordered as the relationship sorts them), `phases`,
   `currentPhase`, and each `Phase`'s `actions`. It applies no filter of its
   own: what the Player, Action and Game policies allow is what is returned.
9. `Game` gains a public calculation `my_seat` (GraphQL `mySeat`), a
   `Player` struct or `nil`: the caller's own seat in that game, read with
   the caller as actor, so the seat's `role` follows the ordinary Player
   field policy (the caller sees their own role). It is `null` for a caller
   with no seat (which cannot happen on a game the caller can read, but is
   the defined answer). A module calculation reading `Games.list_players`
   authorized, like `VoteTally`, is the expected shape; a filtered
   relationship using `^actor(:id)` is unverified and the coder may only use
   it if a test proves it.
10. `Phase.vote_tally` is exposed as the generated `voteTally` field, a JSON
    string of the calculation's map. No other tally logic is added.

### Shared resolution of "the caller's seat and the open phase"

11. One shared module (name at the coder's choice) resolves, for a `game_id`
    and the caller: the game (`Games.get_game/2` with `load: [:current_phase]`
    and `actor:` the caller, authorized) and the caller's seat
    (`Games.list_players/1` with a `game_id`/`user_id` filter and `actor:` the
    caller). It returns the seat and, where the caller asks for it, the open
    phase. It never bypasses policies with `authorize?: false`; like the
    `async?: false` rule in CLAUDE.md, this is checked by reading it in
    review, no test can see it.
12. When the game cannot be read by the caller (unknown id, or the caller has
    no seat in it) the resolution fails with an invalid-input error on
    `:game_id`. The two cases are indistinguishable by design: no game id can
    be probed.
13. When the game has no open phase (lobby, or finished) an action that
    needs one fails with an invalid-input error on `:game_id`, and no `Action`
    row is written.

### In-game mutations (generic actions on `Action`)

14. `Action` gains generic actions `:cast_vote`, `:cast_kill`,
    `:cast_investigation`, `:cast_protection` and `:cast_shot`, each with
    arguments `game_id` and `target_id` (both `uuid`, required), returning
    an `Action` (`:struct`, `instance_of: Action`). They are exposed as the
    mutations `vote`, `kill`, `investigate`, `protect`, `shoot`, with flat
    arguments `gameId`, `targetId` (`args [...]`) and
    `error_location :in_result`, so every mutation answers
    `{ result, errors }` like the create/update mutations.
15. Each of them resolves the seat and the open phase (rules 11-13), then
    calls the existing code interface as the caller and returns its result:
    `:cast_vote`, `:cast_investigation`, `:cast_protection`, `:cast_shot` call
    `Games.create_action/5` with types `:vote`, `:investigate`, `:protect`,
    `:shoot`; `:cast_kill` calls `Games.create_kill_action/4`. Each passes the
    caller as `actor` and the caller's seat id as `actor_id`. No rule check
    (aliveness, role, phase kind, one action per phase, one kill identity,
    consecutive protection, the pending-hunter check, target-in-game) is
    written again; their errors come back unchanged, on their own fields
    (for example `targetId`).
16. A vote or protection cast again while allowed is the qss.21 upsert, done
    by the same call: the same row is returned with the new target. That is
    what "change a vote" means over GraphQL; there is no separate
    `changeVote`.
17. `Action` gains generic actions `:withdraw_own_vote` and
    `:withdraw_own_protection`, each with one argument `game_id`, exposed as
    `withdrawVote` and `withdrawProtection` (flat `gameId`, in-result errors,
    boolean result). Each resolves the seat and open phase and calls
    `Games.withdraw_action/4` as the caller with type `:vote` / `:protect`.
    Withdrawing when nothing was cast, in an open day, succeeds and changes
    nothing (`:withdraw`'s own contract).
17a. Both withdrawals require the open phase to be a `:day` phase. When the
    open phase is a night (including the night that opens at dusk, where a
    call would otherwise be a silent no-op returning `true`), or there is
    none, the call is refused with an error on `:game_id` and nothing is
    deleted. The wrapper checks this before calling
    `Games.withdraw_action/4`; `:withdraw`'s own rules are unchanged.
18. A caller with a seat whose named target is in another game gets the
    `ActorAndTargetInGame` error on `targetId`; a dead caller gets the
    existing not-alive error on their own actor field; a wrong phase kind
    (for example a `vote` at night) gets the existing phase-kind error. All
    are existing validations, only surfaced.
19. All seven new `Action` generic actions are named in `Action`'s policies
    with `authorize_if actor_present()`: a request with no bearer token fails
    with a `forbidden` error in `errors` and runs nothing. The real
    authorization is the inner call's existing policy (`actor.user_id ==
    ^actor(:id)`, and `WithdrawNamesOwnSeat`), which still applies because the
    caller is passed as `actor`.

### Lobby mutations

20. `Game` gains a create action `:open` (code interface
    `Games.open_game/2`), exposed as `createGame` with flat arguments `name`,
    `timezone`, `dayStart`, `dayEnd`. It accepts exactly `name`, `timezone`,
    `day_start`, `day_end`; there is no `joinCode` or `ownerId` input. Omitted
    `timezone`, `day_start` and `day_end` take the attribute defaults. The
    `players` argument that `SeatOwner`/`manage_relationship` use is not
    public.
21. `:open` sets `owner_id` with `set_attribute(:owner_id, actor(:id))` (no
    client value; `relate_actor` is too late for `SeatOwner`, which reads the
    `owner_id` attribute and so must run after this change), keeps the
    existing `SeatOwner` change so the owner is seated, and applies every
    existing `Game` validation. A caller with no token gets a `forbidden`
    error (`actor_present()` policy on `:open`) and no game.
22. `:open` sets `join_code` from a new change. It draws candidates of
    exactly 6 uppercase characters from the alphabet
    `ABCDEFGHJKMNPQRSTUVWXYZ23456789`. For each candidate it asks
    `Games.get_game_by_join_code/2` (`authorize?: false`, the lookup
    `ResolveGameByJoinCode` already uses) and takes the first candidate that
    matches no game. After 10 candidates all taken, the action fails on
    `:join_code`. The residual race between that check and the insert is left
    to the `unique_join_code` identity's own error; no second retry layer.
23. The candidates come from `changeset.context[:join_code_candidates]` when
    that is a list (consumed in order, for tests, passed through
    `Games.open_game(params, context: %{join_code_candidates: [...]})`),
    otherwise from `Enum.random/1` over the alphabet. A client cannot set
    `changeset.context`, so it cannot pick its own code.
24. `Player` gains a generic action `:join_as_self` (code interface
    `Games.join_as_self/2`) with argument `join_code`, returning a `Player`,
    exposed as `joinGame(joinCode)`. It upcases `join_code`
    (`String.upcase/1`), then calls `Games.join_game/3` with the caller's own
    id as `user_id` (read from the actor, the same value
    `set_attribute(:user_id, actor(:id))` would give; never an input) and the
    caller as `actor`, so
    `GameInLobby`, `UserHasName`, `GameNotFull`, the unknown-code error and
    the unique seat all apply unchanged and come back on their own fields
    (`joinCode`). Named in `Player`'s policies with `actor_present()`; no
    token gives `forbidden`.
25. `Player` gains a generic action `:leave_as_self` (code interface
    `Games.leave_as_self/2`) with argument `game_id`, returning a boolean,
    exposed as `leaveGame(gameId)`. It resolves the caller's seat (rules 11,
    12; the open-phase part of rule 13 does not apply, a lobby has none) and
    calls `Games.remove_player/2` on that seat as the caller, so the existing
    `GameInLobby` validation refuses leaving once the game has started or
    finished. Named in `Player`'s policies with `actor_present()`.
26. `leaveGame` by the game's owner fails with an invalid-input error on
    `:game_id`, and the seat stays. This is a new validation on the generic
    action, working on an `Ash.ActionInput`, comparing the game's `owner_id`
    with the caller. `Games.remove_player/2` itself is unchanged and still
    removes an owner's seat when called internally.
27. `startGame` exposes `Game :start` as an update mutation (argument `id`),
    with `hide_inputs [:now]` so a client cannot move the clock. A
    non-owner seated in the game gets a `forbidden` error, an unseated
    caller a not-found error, and no token an error; all in `errors`. The
    existing `ActorIsOwner`, `MinimumPlayers`, `RoleCompositionFits` rules
    apply unchanged.
28. `updateGameSettings` exposes `Game :update_settings` as an update
    mutation (argument `id`), accepting exactly that action's `accept` list.
    Owner only, lobby only, as today (`relates_to_actor_via(:owner)`,
    `ActorIsOwner`, `attribute_equals(:state, :lobby)` and the qss.14
    validations), all unchanged.

### Authorization of every reachable write

29. Every write reachable over GraphQL is authorized by the actor:
    `createGame` (`actor_present()`), `joinGame`, `leaveGame`, the five
    action mutations and two withdrawals (`actor_present()` plus the inner
    call's policy), `startGame` and `updateGameSettings` (the owner policy).
    The actions that stay `authorize_if always()` (`Game :create/:update/
    :destroy/:finish/:end_day/:end_night`, qss.7's `:resolve_hunter_deadline`, `Player :create/:join/:update/
    :destroy`, `Action :update/:destroy`) are none of them exposed (rule 3),
    and their policies are not changed in this bead.
30. Every new action (the seven `Action` ones, `Player :join_as_self` and
    `:leave_as_self`, `Game :open` and `:mine`) is named in its resource's
    `policies` block, so `Ash.Policy.Authorizer`'s default-deny does not
    refuse it. `:mine` needs no extra policy: the existing
    `action_type(:read)` policy covers it.

### Visibility over GraphQL

31. Nothing is loaded with `authorize?: false` on the way to a response, and
    `AshGraphql.Domain`'s `authorize?` stays at its default `true`.
    Consequently: another player's `role` comes back `null` with a
    `forbidden_field` entry in `errors` (data otherwise intact) unless the
    existing Player field policy allows it (own seat, fellow werewolf's
    wolf row, finished game, dead reader); `:kill`, `:investigate` and
    `:protect` rows appear in `actions` only for the readers the Action
    read policy allows (werewolves, the seer who cast it, the bodyguard who
    cast it, and any dead reader); and `voteTally` is the narrowed map of
    qss.16 (a living reader: counting votes plus their own non-counting one;
    a dead reader: everything; no seat: `{}`).
32. `Player.performed_actions` and `targeted_by_actions` are reachable
    through the generated relationships; because they load through the same
    authorized read they show only the `Action` rows the reader may see
    (rules 31, 33). No `hide_fields` is added for them.
33. The `Action` read policy narrows `:vote` rows: a living seated reader
    reads a `:vote` row only when its voter and its target are both alive,
    or when the row's voter is the reader's own seat; a dead seated reader
    reads every `:vote` row; a reader with no seat reads none. `:shoot` rows
    stay readable to every seated reader, and the `:kill`, `:investigate` and
    `:protect` conditions are unchanged. This holds on every read path
    (`Games.list_actions/1`, `Games.get_action/2`, `Phase.actions`,
    `Player.performed_actions`, `Player.targeted_by_actions`), not only
    `voteTally`. It is the narrowing `Phase.vote_tally` already applies
    (qss.16 rule 4), now enforced at the row. `VoteTally`'s own authorized
    read keeps returning the same map: the rows it now loses are ones its
    narrowing dropped anyway.

## Out of scope

- Chat: `Message` type, `sendMessage`, history, subscription: 27w.6.
- Subscriptions (live game updates): 27w.4.
- Mobile screens and hooks using the new operations: o25.4, o25.5. The
  regenerated `mobile/schema.graphql` and `mobile/src/gql` are in scope; no
  new `.ts`/`.tsx` documents are.
- Hiding `Player.alive` from living readers until dawn: qss.19 (owner
  decision 8).
- Exposing `end_day`, `end_night`, `finish`, `resolve_hunter_deadline`,
  `Game :update/:destroy`, `Player :update`, `Action :update`: never exposed;
  the phase scheduler is qss.9.
- Tightening the policies of the internal actions (`authorize_if always()`):
  no bead; they are unreachable over GraphQL and are called by reactors,
  `DealRoles`, `ApplyKill` and tests.
- Typed GraphQL enums for `Role`, `Action.Type`, `Phase.Kind`, `Winner`,
  `RoleDistributionMode` (they stay strings), and a typed shape for
  `voteTally`/`Action.result` (they stay `JsonString`): no bead.
- A "regenerate join code" mutation, or joining
  by game id: no bead.
- Pagination or filtering of `myGames`, and a game-level "kick".
- A rate limit on `joinGame` code guessing: no bead.
- Rewriting any rule check, or changing `Games.create_action/5`,
  `create_kill_action/4`, `withdraw_action/4`, `join_game/3`,
  `remove_player/2` or `start_game/3`.
- Editing `auth_test.exs` to share its helpers: new helpers go in
  `test/support`, the existing test file is untouched.

## Acceptance

Direct unit tests, each on its own contract (a handful each, not a matrix):

- `Games.open_game/2` - seats the caller as owner and sets `owner_id` to
  them; no actor is refused; join code is 6 characters, all in the alphabet;
  with `context: %{join_code_candidates: [taken, free]}` and a game already
  holding `taken`, the game gets `free`; with 10 candidates all taken it
  fails on `:join_code`; a supplied `owner_id` or `join_code` in params is not
  accepted.
- The join-code change (name at the coder's choice) - the candidate
  selection above, tested directly against a changeset, plus the random path
  (result matches the alphabet and length).
- `Games.my_games/1` - only the caller's games, all states, newest
  `inserted_at` first; `[]` for a user with no games and for no actor.
- The shared caller-resolution module - returns seat and open phase for a
  seated caller; fails on `:game_id` for an unknown game, an unseated
  caller and no actor; fails on `:game_id` for a lobby or finished game
  when a phase is required.
- `Games.cast_vote/3`, `cast_kill/3`, `cast_investigation/3`,
  `cast_protection/3`, `cast_shot/3` (code interface names as defined, args
  `game_id`, `target_id`) - each lands the matching action for the
  caller's seat in the open phase; each returns the existing validation's
  error unchanged for a wrong-role caller and for a target in another game;
  `cast_vote` twice returns the same row with the new target (qss.21);
  `cast_kill` twice in a night refuses the second (one-kill identity);
  `cast_shot` works for the pending hunter and is refused for anyone else
  (qss.7); no actor is refused.
- `Games.withdraw_own_vote/2` and `withdraw_own_protection/2` - delete the
  caller's own row in an open day; succeed as a no-op with none; refused for
  a dead caller; refused on `:game_id` when the open phase is a night
  (right after `end_day`) or there is none.
- `Action` read policy (`Games.list_actions/1`, `Games.get_action/2`) - a
  living reader reads a counting `:vote` row and their own non-counting one,
  and not a dead voter's or a vote for a dead target; a dead reader reads
  all of them; an outsider none; `:shoot` still readable to all seated.
- `Games.join_as_self/2` - seats the caller by code; unknown code, started
  game, nameless user, full game each fail on the existing field; no actor
  refused.
- `Games.leave_as_self/2` - removes the caller's own seat in a lobby;
  refused for the owner (seat remains); refused once started; refused for an
  unseated caller.
- The owner-cannot-leave validation - passes for a non-owner, fails on
  `:game_id` for the owner, and accepts an `Ash.ActionInput` subject.
- `Games.start_game/3` and `Games.update_game_settings/3`: unchanged; the
  existing tests stand.
- `Games.get_game/2` with `load: [:my_seat]` - the caller's own seat, with
  their role visible; another reader gets their own seat, not the first
  player's.
- Schema tests (introspection through Absinthe, no DB): no argument or
  input field in the schema is named `actorId`, `userId`, `ownerId`,
  `phaseId`; the mutation names asserted for rule 3 are absent; the mutation
  names of rules 14, 17, 20, 24-28 are present with exactly their arguments;
  `startGame` has no `now` input; `User.email` is nullable.

GraphQL tests through `/gql` as a signed-in player (new helper module in
`test/support`: request a magic link for a seeded, named user, sign in, put
`authorization: Bearer ...` on the conn, modelled on `AuthTest`'s
`request_token`/`sign_in`; games are staged through the domain). Every
mutation gets its negative cases, and each of these is its own test:

- `createGame`: happy path returns a game with a 6-character `joinCode` and
  `mySeat` non-null; no token gives a `forbidden` error and no game.
- `joinGame`: happy path (also with the code lower-cased); unknown code; no token; game already started.
- `leaveGame`: happy path; owner refused; no token; unseated caller;
  started game refused.
- `startGame`: owner happy path (state moves to `day`/`night`); a seated
  non-owner refused; no token; an unseated caller.
- `updateGameSettings`: owner happy path in the lobby; non-owner refused;
  refused after start.
- `vote`: happy path; no token; a caller seated in a different game than the
  one named (rule 12); the wrong phase (a `vote` at night); a dead voter; a
  second `vote` changes the target, not the row count.
- `withdrawVote`: deletes the vote; no token; dead caller; refused on
  `gameId` at night (after `Games.end_day/2`) with the vote row untouched.
- `kill`: a werewolf lands it; a villager caller refused; a second kill the
  same night refused; a dead wolf refused; no token.
- `investigate`: the seer gets the answer in `result`; a non-seer refused;
  a day-time call refused; a dead seer refused; a second call refused.
- `protect`: the bodyguard's happy path (day); a non-bodyguard refused; the
  same target two days in a row refused; a night call refused; a dead
  bodyguard refused.
- `withdrawProtection`: deletes it in the day; refused at night with the
  row untouched.
- `shoot`: the pending hunter's shot lands (game staged with qss.7's pointer
  set); a non-hunter refused; no pending window refused; a dead target
  refused.
- A caller with no open phase (a game in the lobby) calling `vote`
  gets an error on `gameId` and no row is written (rule 13).

Visibility tests through `/gql`, one per hidden field or row, each also
asserting the visible counterpart so the test would fail if the policy were
removed or if the field were always hidden:

- `role` of a wolf hidden from a villager (`null`, `forbidden_field` in
  `errors`, the villager's own role and the game still returned); visible to
  a fellow wolf; visible to everyone once the game is finished; visible to a
  dead reader.
- `role` of a non-wolf (the seer) hidden from a living werewolf.
- another player's `user { email }` is `null` while `user { name }` is
  present, and the game and player list still load (rule 5); the caller's own
  `email` is present.
- a `:kill` row absent from `phases { actions }` for a villager, present for
  a werewolf, present for a dead villager.
- an `:investigate` row absent for everyone but the seer (a wolf, a villager),
  present for the seer and for a dead reader.
- a `:protect` row absent for everyone but the bodyguard, present for the
  bodyguard.
- the same `:kill` row absent from a villager's view of a wolf's
  `performedActions` (rule 32).
- a dead voter's `:vote` row (and a vote for a dead target) absent from a
  living reader's `phases { actions }`, present for a dead reader; the
  reader's own non-counting vote present for them.
- `voteTally` for a living reader omits another voter's non-counting vote
  and keeps the reader's own; a dead reader sees both (JSON string decoded
  in the test); a caller with no seat gets `game(id) = null`.
- `game(id)` and `myGames` for a caller with no seat: `null` and `[]`, no
  `errors`.
- `Phase.summary` is not a field (introspection or a rejected query).

End to end: three or more users sign in; one calls `createGame` (a code is
returned), the others `joinGame` with it, the owner calls `updateGameSettings`
then `startGame`; roles are read with `game(id) { mySeat { role } }`; a wolf
`kill`s, a villager `vote`s and `withdrawVote`s, the day is ended through
`Games.end_day/2` (not GraphQL), `myGames` lists the game first; every step
is a GraphQL request with only game ids and target ids as inputs.

`mix graphql.codegen` is run and its output (`mobile/schema.graphql`,
`mobile/src/gql/*`) is committed; `mix ash.codegen --check` and `mix lint`
are clean. No migration is expected (no attribute added by this bead).

## Touches

Advisory: the coder may deviate. Files the rules will probably reach:

- `lib/werewolf_ash/games.ex` (`AshGraphql.Domain`, the `graphql` block,
  new code interface entries `open_game`, `my_games`, `join_as_self`,
  `leave_as_self`, `cast_*`, `withdraw_own_*`)
- `lib/werewolf_ash/games/game.ex` (extension, `graphql` section, `:open`,
  `:mine`, `my_seat` calculation, policies)
- `lib/werewolf_ash/games/player.ex` (extension, `graphql` section,
  `:join_as_self`, `:leave_as_self`, policies)
- `lib/werewolf_ash/games/phase.ex` (extension, `graphql` section,
  `hide_fields [:summary]`)
- `lib/werewolf_ash/games/action.ex` (extension, `graphql` section, seven
  generic actions, policies)
- `lib/werewolf_ash/accounts/user.ex` (`nullable_fields [:email]`)
- `lib/werewolf_ash_web/graphql_schema.ex` (domain list)
- new files under `lib/werewolf_ash/games/game/changes/` (join code),
  `.../game/calculations/` (`my_seat`), `.../player/validations/` (owner
  cannot leave), `.../player/actions/` and `.../action/actions/` (the
  generic-action implementations and the shared resolution module)
- `mobile/schema.graphql`, `mobile/src/gql/gql.ts`, `mobile/src/gql/graphql.ts`
  (regenerated; `mobile/src/gql/index.ts` if it changes)
- new tests: `test/werewolf_ash_web/graphql/games_test.exs` (and a
  visibility test file), unit tests beside each new module, and a helper in
  `test/support/` (`graphql_helpers.ex`)
- `CLAUDE.md` (the rule text above; the owner edits it, coders are refused)

### Existing tests a rule will break

Rule 33 (Action read policy, `lib/werewolf_ash/games/action.ex`). Greps run:
`grep -rn "list_actions\|get_action" test | grep -v "authorize?: false"` and
`grep -rn "load: :vote_tally" test`. Readers with an actor:
`test/werewolf_ash/games/action/policy_test.exs:140,145,149-216`,
`policy_end_to_end_test.exs:90,100`, `games_test.exs:1161-1276` and `:1283-1325` (vote_tally
loads with an actor), and `vote_tally_test.exs:45-160` (through
`VoteTally.calculate/3`). The `list_actions!` calls in `action_test.exs:315,
339,473,491,900,1040`, `withdraw_test.exs:21` and `vote_tally_test.exs:63`
use `authorize?: false` or read non-vote rows, so are unaffected.
- `policy_test.exs:183-186` ":vote is readable by any game member": still
  passes (the villager reads their own vote; the wolf reads a row whose voter
  and target are alive) but its title is stale. Rename it to "a counting
  :vote is readable by any game member" and add rule 33's negative cases
  (dead voter, dead target, own non-counting row, dead reader).
- `games_test.exs:1161-1276` and `vote_tally_test.exs:45-160`: the maps are
  unchanged, because the rows the policy now drops are the ones
  `VoteTally.narrow/2` dropped. The coder confirms by running them; a failure
  there means rule 33 is wrong, not the tests.


Grep run for callers of every action whose policy or signature this bead
could touch:

`grep -rn "join_game\|remove_player\|create_game\|destroy_game\|update_game(\|finish_game\|start_game\|update_game_settings\|list_games\|update_player" lib test`
(counts by file: `join_game` 18 hits in `games_test.exs` and
`game/policy_test.exs:72`; `remove_player` `games_test.exs:530,558,570`,
`message_test.exs:181`; `destroy_game` `games_test.exs:589`,
`message_test.exs:173`; `list_games` `game/policy_test.exs:21,42,54`;
`update_player` 74 hits in 20 files, in `lib`: `resolve_lynch.ex:136`,
`deal_roles.ex:38`, `apply_kill.ex:39`).

- No rule changes the behaviour or the policy of any of those existing
  actions: rule 29 leaves every `authorize_if always()` policy as it is, and
  rules 20-28 add new actions instead of changing `:create`, `:join`,
  `:destroy`, `:start` or `:update_settings`. So none of these tests, nor
  `DealRoles`, `ApplyKill` and `ResolveLynch`, is affected. I have not changed
  a return value that a caller reads.
- The only existing behaviour that changes is the GraphQL schema itself and
  the `email` field's nullability. Grep run:
  `grep -rn "email" mobile/src/graphql` finds `auth.ts:11,37`, which only
  select `email` and compile unchanged against a nullable field.
  `grep -rn "currentUser\|signInWithMagicLink" test` (all in
  `test/werewolf_ash_web/graphql/auth_test.exs`) read `email` for the caller's
  own row, which the field policy still allows, so they are unchanged.
- `test/werewolf_ash/games/enum_docs_test.exs` iterates four enum modules for
  a moduledoc; no rule touches it.
- Adding `AshGraphql.Resource` to `Game`, `Player`, `Phase`, `Action` makes
  `mix graphql.codegen` regenerate `mobile/schema.graphql`; any stale
  committed copy is the stale side, not a rule.

## Verified against `deps/`

- A forbidden attribute resolves to `null` plus a `forbidden_field` error
  in `errors` in the default (`:legacy`) mode, and a non-nullable field
  that is forbidden nulls its parent:
  `deps/ash_graphql/lib/graphql/resolver.ex:3355-3380` (`resolve_attribute`)
  and `deps/ash_graphql/documentation/topics/authorize-with-graphql.md`
  ("Field Policies", "nullability" warning). `nullable_fields` is the
  documented remedy (`lib/resource/resource.ex:572`).
- `get` and `read_one` queries default to `allow_nil?: true`, so a read
  filtered by policy is `null`, not an error: `lib/resource/query.ex:129-133`.
- Generic actions can be mutations with `args` (flat arguments) and
  `error_location :in_result` (a `{result, errors}` shape):
  `lib/resource/resource.ex:88-93,141-165,2248-2254`; an `:ok` return is
  `true`: `lib/graphql/resolver.ex:69-71`. A `:struct` return with
  `instance_of` a resource is typed as that resource:
  `lib/resource/resource.ex:5953-5955`.
- `hide_inputs` exists on mutations: `lib/resource/mutation.ex:23,63`.
  `Ash.Type.Atom` is a GraphQL `String`, and an `Ash.Type.Enum` with no
  `graphql_type/1` is a string too (`resource.ex:5905-5911`,
  `documentation/topics/use-enums-with-graphql.md`); a plain `:map` is
  `JsonString` (`resource.ex:5916-5923`, `lib/types/json_string.ex`).
- Nested relationship loads carry the parent's `authorize?` and actor
  (`deps/ash/lib/ash/actions/read/relationships.ex:215,275,335`), and the
  relationship default `authorize_read_with: :filter` drops hidden rows
  silently (`deps/ash/lib/ash/resource/relationships/has_many.ex:35`).
- Update and destroy mutations return a forbidden error rather than
  "not found" because `config/config.exs:6` sets
  `authorize_update_destroy_with_error?: true`
  (`lib/graphql/resolver.ex:2046`).

Unverified (labelled as assumptions for the coder to prove with the tests
above, and to report if wrong): that the record `createGame` returns is
read back with the new owner seat already committed, so `mySeat` and
`players` resolve on the create result; that AshGraphql accepts a public
`:struct` calculation on `Game` with `instance_of: Player` (the code at
`resource.ex:5953` says so, but no test in the repo does it yet); and that
a generic action's `validate` given an `Ash.ActionInput` runs before `run`
(`ActorAlive` already relies on this for `:withdraw`).
