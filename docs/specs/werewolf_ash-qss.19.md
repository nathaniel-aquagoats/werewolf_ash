# werewolf_ash-qss.19: Day and night announcements: dawn death report with roles, dusk notice

Depends on: werewolf_ash-27w.3

## For the owner

**What changes.** The game now tells everyone what happened, at the moment it
happens. At dawn the village hears who died in the night and what each one
was. At dusk it hears who was lynched and what they were, or that nobody was,
and that night is starting. A hunter's shot is announced at once, and a
finished game announces its winner. Until dawn, a night victim still looks
alive to living villagers; the victim and the wolves see the truth. Players
read all of this over GraphQL with an `announcements` query.

**Decisions.**
1. Where are announcements stored? — **Decided:** a new `Announcement` record
   per game (kind dawn / dusk / shot / game_over, the deaths with their roles,
   a time), readable by every seat including the dead, never by non-members;
   it is the public half of qss.11's later event feed; no chat system
   messages (2026-09-29).
2. The hunter's shot? — **Decided:** announced at once with victim and role,
   whenever it lands; `:shoot` rows stay visible to every seat (2026-09-29).
3. Dusk? — **Decided:** the dusk notice always states the lynch outcome, "no
   one was lynched" on a tie or no votes included; a game won by the lynch
   gets a `game_over` with the winner instead of a night-start notice
   (2026-09-29).
4. Scope? — **Decided:** includes GraphQL (`announcements` query, hidden-alive
   rule applied there); live push stays with 27w.4 (2026-09-29).
5. Night deaths hidden until dawn? — **Decided:** yes; living non-wolf readers
   see a night victim as alive until the dawn announcement; the victim's own
   seat, the wolves, dead readers and finished games see the truth
   (2026-09-28).
6. Every lynch reveals the lynched role at dusk — **Decided** (2026-09-28).
7. How is a death recorded in an announcement? — **Decided:** a list of
   entries, each the player, the role they held and a cause (lynched, killed,
   shot), with no link to the live player, so an announcement can never show
   more than it says (2026-09-29).
8. Does every way a game can finish produce a `game_over`? — **Decided:** yes:
   lynch, dawn check, wolf kill, hunter's shot, the deadline fallback and a
   direct finish. It carries only the winner, lists no deaths and adds no
   reveal of its own: every role is visible because the game is finished
   (27w.2, qss.17's job, already done), so nothing is revealed twice
   (2026-09-29).
9. When is a death "announced"? — **Decided:** a private mark on the player
   row, set when an announcement lists them; it drives both "role becomes
   public" and "no longer hidden" (2026-09-29).
10. How does a living reader see a hidden victim as alive? — **Decided:** over
    GraphQL `alive` becomes a computed value that says true for an unannounced
    night victim when the reader is a living non-wolf in a running game; the
    stored flag is untouched, so every game rule still uses the truth
    (2026-09-29).
11. Does the hidden death leak through votes? — **Decided:** it would, so for
    living readers a player counts as alive for vote visibility until their
    death is announced. Dead readers see the real state, and the lynch itself
    is unchanged (2026-09-29).
12. Does the dawn report appear when nobody died? — **Decided:** yes, with an
    empty list, and the dusk one always (2026-09-29).
13. The shot's time? — **Decided:** the wall clock when the shot lands; dawn
    and dusk use the transition's `now`; `game_over` the wall clock
    (2026-09-29).
14. Order of announcements? — **Decided:** creation order (`inserted_at`),
    with `game_over` always last. Not `announced_at`: a shot uses the wall
    clock while dawn and dusk use the injected `now`, so the two can disagree
    (2026-09-29).
15. Does a shot notice also report an earlier, unannounced night victim? —
    **Decided:** no, only the shot victim; the night victim waits for dawn
    (2026-09-29).
16. A night victim being unable to post in chat while everyone else can —
    **Decided:** accepted, not hidden (2026-09-29).
17. May the seer investigate a night victim before dawn? — **Decided:** yes.
    The investigation succeeds, gives the victim's real werewolf yes/no and
    spends the seer's night action. Only a player killed by this night's
    landed wolf kill and not yet announced qualifies; every other dead target
    is still refused (2026-09-29).

**Rule changes.** Add to CLAUDE.md, under Conventions & Patterns, after "Deaths
are announced":

> - Announcements (owner decisions 2026-09-29): every announcement is an
>   `Announcement` row (dawn, dusk, shot, game_over), created by the game's
>   rules inside the transition's own transaction, readable by every seat of
>   the game and by no one else. A death is announced when a row lists it: a
>   night kill at dawn, a lynch at dusk, a hunter's shot at once. Until then
>   the victim of a night kill reads as alive to living non-wolf readers, in
>   every field and every vote view; the victim's seat, the wolves, dead
>   readers and finished games see the truth. A dead player's role is public
>   from the moment their death is announced.

Change to the "Deaths are announced" bullet: nothing is removed; the dusk
lynch reveal it already states is now delivered by the dusk announcement.
Change to 27w.3 rule 33 (Action read policy) as amended by rule 21 below.

## Goal

The village is told what the world did, when it did it. Dawn reports the
night's deaths with their roles; dusk reports the lynch (or that there was
none) and that night begins, or hands over to a `game_over` with the winner
when the lynch ended the game; the hunter's shot is reported the instant it
lands. Every seat of the game, dead included, can read these, outsiders
cannot, and over GraphQL they come in order. A night's death stays invisible to
living villagers, in players, votes and tallies, until the dawn report
names it.

## Rules

Terms: "announced" means the player's private `death_announced_at` is
non-nil. "Unannounced death" is `alive == false` and not announced. "Reader"
is the Ash actor; a "living non-wolf reader" holds a living, non-werewolf seat
in the game. All creation below uses `authorize?: false`, inside the
transition's own transaction, so a failure rolls the transition back.

### The resource

1. `Announcement` is a new Games resource (generated with
   `mix ash.gen.resource`, in the domain, Postgres-backed) with: `game`
   (belongs_to, required, `on_delete: :delete` so destroying a game removes
   them), `kind` (enum `dawn | dusk | shot | game_over`), `announced_at`
   (`utc_datetime_usec`, required), `deaths` (array of the embedded resource in
   rule 2, default `[]`), `winner` (the existing `Game.Winner`, nil unless
   `game_over`), `lynch_outcome` (`lynched | no_lynch`, nil unless `dusk`) and
   `night_starting` (boolean, default false, true only on a `dusk` whose game
   continued). Every field except the primary key and timestamps is public.
2. `Announcement.Death` is an embedded resource with `player_id` (uuid),
   `role` (existing `Player.Role`, nil allowed) and `cause` (enum `lynched |
   killed | shot`). It has no relationship to `Player`, so it can carry no
   later state.
3. A reader holding any seat in the announcement's game, living or dead,
   reads every announcement of that game. A reader with no seat, and no actor
   at all, reads none, and gets an empty list rather than an error.
4. No actor may create, update or destroy an announcement: none of those
   actions is named in a policy that allows an actor, so a seated actor
   calling the create action with authorization on is refused. The one create
   action (`:announce`) is used only by game rules with `authorize?: false`.
5. The primary read returns announcements in creation order (`inserted_at`
   ascending, `id` as tiebreak) with `game_over` always last. It does not sort
   by `announced_at`: a shot uses the wall clock and dawn and dusk the injected
   `now`, so they can disagree. (A winning lynch creates `game_over` inside the
   vote resolution, before the dusk notice is written.)
6. `Player` gains a private (not `public?`) `utc_datetime_usec` attribute
   `death_announced_at`, nil by default. It is set only by rules 8, 11 and 13,
   to the announcement's `announced_at`, on exactly the players the
   announcement lists. `game_over` sets none.

### Dawn

7. `end_night` creates exactly one `dawn` announcement in its transaction,
   always, with `announced_at` = the action's `now`, `night_starting` false and
   no `lynch_outcome`.
8. Its `deaths` are exactly the game's players with an unannounced death at
   that moment, each with the role they were dealt and cause `killed`; each is
   then marked announced (rule 6). If nobody qualifies, `deaths` is `[]`.
   A player already listed by an earlier announcement (a lynch, a shot) is
   never listed again.
9. A dawn announcement is created whether or not the dawn win check finished
   the game; when it did, rule 15's `game_over` also exists.

### Dusk

10. `end_day` creates exactly one `dusk` announcement in its transaction,
    always, with `announced_at` = the action's `now`. It reads nothing about
    phases: not a Phase row, not `phase_ends_at`.
11. When exactly one player was alive before `end_day` started and is dead
    after its vote resolution, that player is the lynched one: `lynch_outcome`
    is `lynched`, `deaths` is that one entry with their role and cause
    `lynched`, and they are marked announced. Otherwise (tie, no votes)
    `lynch_outcome` is `no_lynch` and `deaths` is `[]`. A player who was
    already dead before `end_day` is never the lynched one and is not listed.
12. `night_starting` is true when the game's state after `end_day`'s win
    check is not `:finished`, and false when it is. A game won by the lynch
    therefore has a `dusk` announcement with `night_starting` false and a
    `game_over`; it never says night is starting.

### The hunter's shot

13. Every landed `:shoot`, chosen or the deadline fallback, creates one `shot`
    announcement in the shot's own transaction: `deaths` is exactly the shot
    player (role, cause `shot`), `announced_at` is the wall clock at that
    moment (`:shoot` has no `now`), the victim is marked announced, and it
    exists whether or not the shot's win check finished the game. It does not
    list any other unannounced death.
14. A refused `:shoot` (rule 10 of qss.7, dead target and the like) creates no
    announcement.

### Game over

15. Every transition into `:finished` creates exactly one `game_over`
    announcement whose `winner` is the game's winner: the `Game :finish`
    action carries it, so the dusk lynch, the dawn win check, the wolf kill,
    the hunter's shot, the deadline fallback and a direct
    `Games.finish_game/2` all produce it. It has `deaths` `[]`, `night_starting`
    false, `announced_at` the wall clock at that moment. A game has at most
    one, since `finish` runs once.
16. `game_over` marks no death announced and reveals no role by itself:
    every role is visible in a finished game through the existing
    `Player.role` policy, which is qss.17's reveal and is not changed.
17. A game finished mid-night keeps its `phase_ends_at`, and a game finished
    by the dusk lynch has no night phase: no announcement reads either. Neither
    produces an announcement kind or content that differs from rules 10-15.

### Role visibility

18. `Player.role` gains one more grant: readable by any reader seated in the
    game when the player is announced. A living villager cannot read the role
    of a night victim before dawn and can read it after; can read a lynched
    player's role right after `end_day`, and a shot player's role right after
    the shot; and a dead player who was never announced (killed directly with
    `update_player`) is still hidden. The existing grants are unchanged.

### Hidden night death

19. `Player` gains a public boolean calculation `visible_alive`, an
    expression, that is true when `alive`, and otherwise true only when all of
    the following hold: the player is not announced, the game is not
    `:finished`, and the reader holds a living seat in the game that is not a
    werewolf. It is false for: the victim reading their own seat, a werewolf
    reader, a dead reader, any reader in a finished game, an announced dead
    player, and no actor.
20. Over GraphQL `Player`'s `alive` field is `visible_alive`: the attribute is
    hidden with `hide_fields [:alive]` and the calculation is renamed to
    `alive` with `field_names`. It applies on every path that returns a
    `Player` (`game.players`, `mySeat`, an action's actor or target).
    `death_announced_at` is not exposed. The stored `alive` attribute, and the
    domain code interface, are unchanged so every game rule keeps reading the
    truth.
21. Amends 27w.3 rule 33, for LIVING readers only. "Publicly alive" means
    `alive` or unannounced. A living reader reads a `:vote` row (27w.3's
    Action read policy) only when its voter and target are both publicly alive,
    or it is their own. A dead reader still reads every `:vote` row and every
    flag stays real (qss.16 rule 9). `VoteTally.build_entries` therefore keeps
    two flags per entry: `counts` (real aliveness, exactly as today) and a
    public flag (publicly alive). The dead reader's view is unchanged and
    outputs the real `counts`. The living reader's view filters on the public
    flag (plus their own entry) and outputs the public flag as `counts`. The
    no-seat view stays `%{}`. The lynch itself (`ResolveLynch`) keeps the real
    `alive`.
22. Rules 7-13 do not add an announcement before their moment: after a wolf
    kill and before `end_night`, `announcements` has no entry naming the
    victim, and a living villager's `players { alive }` shows the victim
    `true`.

### GraphQL

23. `Announcement` gets `AshGraphql.Resource` (type `:announcement`), the
    embedded `Death` gets type `:announced_death`. A new read action
    `:in_game` with a required `game_id` argument backs the list query
    `announcements(gameId)`, sorted per rule 5, with no pagination. It applies
    rule 3 by policy: a non-member or an unknown id gets `[]`, no `errors`,
    and no token gets `[]`. No mutation is added for announcements.
24. `Game` gains no field for announcements; a client asks `announcements`.

### The seer and a night victim

25. `TargetAlive` gains an option (name at the coder's choice) that the
    `:investigate` clause of `Action :create` passes, and no other clause does.
    With it, a dead target passes when, and only when, all hold: the target is
    not announced, and the phase the action names holds a `:kill` action on
    that target whose `result` is `%{"killed" => true}` (a landed kill in this
    night). The `:kill` lookup is a game-rule read with `authorize?: false`:
    the seer cannot read `:kill` rows under the Action read policy, so an
    actor-scoped read would refuse every case. The investigation is created, `RecordInvestigationResult` gives the
    target's real werewolf yes/no, and it counts as the seer's one
    investigation for the phase (a second is refused).
26. Every other dead target is still refused on `:target_id` for
    `:investigate`: a player killed with `update_player`, a lynched or shot
    player (announced), a night victim already announced, and a target whose
    kill was spent by the bodyguard (they are alive). `:vote`, `:protect`,
    `:shoot` and `:kill` refuse every dead target as today, with no
    exception. `ActorAlive` still applies, so a seer killed in the night
    cannot investigate.

### Finish

27. `Game :finish` gains `require_atomic? false`, because the `game_over`
    hook is an `after_action` that cannot run as a single atomic UPDATE; the
    hook is written as a change that composes with any other hook already on
    `:finish`.

## Out of scope

- Live push of new announcements (subscriptions): 27w.4.
- A chat message per announcement: decided against; the village chat is
  untouched.
- The scheduler and Oban job config: qss.9. This bead adds no job.
- Revealing anything at game over beyond the winner; the finished-game reveal
  is 27w.2's existing rule 5, and `qss.17` is closed.
- The full event feed with private events (seer answers, which wolf killed):
  qss.11. This bead's `Announcement` is the public half only.
- Hiding the victim's silence in chat, or hiding `alive` from the chat
  visibility filter: rule 16 of the card; no bead.
- Hiding any other field of the victim (their `:kill` row and the action
  result are already hidden by 27w.2's Action policy).
- Changing when a hunter window opens, `ResolveLynch`, `ApplyKill`,
  `Games.create_action/5`, `resolve_hunter_deadline.ex`, `AdvancePhase` or
  `HunterWindow`.
- Mobile screens: o25.5. The regenerated `mobile/schema.graphql` and
  `mobile/src/gql` are in scope; new `.ts`/`.tsx` documents are not.
- A separate vote deadline (qss.15): it will have to move rule 11's dusk
  lynch detection (before/after comparison inside `end_day`) to wherever the
  vote then resolves.
- A cause other than `lynched | killed | shot`, or tracking which wolf killed.

## Acceptance

Direct unit tests:

- `Games.create_announcement/2` (params, opts; interface on `Announcement
  :announce`) - with authorization on and a seated actor it is refused; with
  `authorize?: false` it stores kind, deaths, winner, lynch_outcome,
  night_starting.
- `Games.list_announcements/2` (game id, opts; interface on `:in_game`) - a
  seated living reader, a seated dead reader and a seated night victim each
  read them; an outsider and no actor get `[]`; creation order with `game_over`
  last.
- `WerewolfAsh.Games.Announcer.unannounced_deaths/1` (game id) - returns
  exactly the unannounced dead players with roles and cause `killed`; skips
  announced ones; `[]` when none. `Announcer.announce/4` (game id, kind,
  announced_at, attrs map) - creates the row and marks the listed players
  announced, in one call.
- `WerewolfAsh.Games.Game.Changes.AnnounceDawn` - always one announcement;
  lists the night victim with role and cause `killed`; empty when the bodyguard
  saved the target; not the lynched or shot; still produced when the dawn win
  check finished the game.
- `WerewolfAsh.Games.Game.Changes.AnnounceDusk` - `lynched` with role for one
  new death; `no_lynch` on a tie and on no votes; `night_starting` true when
  running and false when the lynch finished the game; ignores an earlier-dead
  player; always exactly one.
- `WerewolfAsh.Games.Action.Changes.AnnounceShot` (registered after
  `ApplyShot`, only for `:shoot`) - one `shot` announcement for a chosen shot
  and one for a fallback; lists only the victim, not an unannounced night
  victim; none for a refused shot.
- `WerewolfAsh.Games.Game.Changes.AnnounceGameOver` (on `:finish`) - every
  route (lynch, dawn check, kill, shot, deadline, `finish_game`) leaves exactly
  one `game_over` with the winner and `[]`.
- `TargetAlive.validate/3` with the new option - passes for an unannounced
  victim of a landed kill in the phase; fails on `:target_id` for a player
  killed with `update_player`, an announced victim, and a target whose kill
  was spent; without the option a dead target still fails. Through
  `Games.create_action/5`: the seer investigates the night victim before dawn
  and gets the real yes/no, a second investigation is refused, and after dawn
  the same call is refused (rule 26).
- `Player` field policy (`role`) — a living villager forbidden before, allowed
  after an announcement, for a lynched, killed, and shot player; a
  `update_player`-killed one stays forbidden.
- `Player.visible_alive` (calculation; read with `load: :visible_alive` and each actor) —
  true for a living villager on an unannounced victim; false for the victim,
  a wolf, a dead reader, in a finished game, and after the announcement; true
  for a living player.
- The vote read policy and `VoteTally.calculate/3` / `Phase.vote_tally` - a
  night victim's day vote, and votes for them, are still shown to a living
  villager, marked `counts: true`, before dawn, and dropped once announced; a
  dead reader sees real `counts` in both cases.
- GraphQL: `announcements(gameId)` as a member, as a dead member, as an
  outsider (`[]`), with no token (`[]`); `players { alive }` and
  `mySeat { alive }` for a villager (`true` for the victim before dawn), for
  the victim and a wolf (`false`), and after dawn (`false`); `role` of the
  victim before and after dawn as a villager; introspection: no `alive`
  argument or mutation, `deathAnnouncedAt` absent.

End to end: through the code interface, a started game plays a night with a
wolf kill, the villager reads the victim alive and role hidden and
`announcements` empty, `end_night` produces a `dawn` naming the victim with
role, the villager now reads the victim dead with the role; a day with a
lynch produces a `dusk` (`lynched`, role, `night_starting` true); a second
game is won at dusk and shows `dusk` (`night_starting` false) then
`game_over`; the same again through GraphQL `announcements` for one path.

Run `mix ash.codegen add_announcements` (new table, new `players` column),
`mix graphql.codegen` and commit the output; `mix ash.codegen --check` and
`mix lint` clean.

## Touches

Advisory: the coder may deviate. Files the rules will probably reach. Note:
`game.ex` and `games.ex` are also in the scheduler bead qss.9's Touches, so
the queue will run the two one after the other; I could not avoid them
(the changes are registered in `Game`'s actions and the interface entries live
in `games.ex`). `advance_phase.ex`, `hunter_window.ex` and
`resolve_hunter_deadline.ex` are deliberately left alone. qss.9 also adds a
hook to `:finish`; the two coexist, each its own change.

- `lib/werewolf_ash/games.ex` (resource and interface entries)
- `lib/werewolf_ash/games/game.ex` (register the three changes; `finish`)
- `lib/werewolf_ash/games/player.ex` (attribute, calculation, field policy,
  GraphQL `hide_fields`/`field_names`)
- `lib/werewolf_ash/games/announcement.ex`,
  `lib/werewolf_ash/games/announcement/*.ex` (new: embedded Death, kind and
  cause enums)
- `lib/werewolf_ash/games/game/changes/` (new: dawn, dusk, game over)
- `lib/werewolf_ash/games/action/changes/announce_shot.ex` (new; `apply_shot.ex`
  itself is not changed)
- `lib/werewolf_ash/games/announcer.ex` (new)
- `lib/werewolf_ash/games/action/validations/target_alive.ex` (rules 25-26)
- `lib/werewolf_ash/games/action.ex` (27w.3 rule 33's vote read policy,
  amended by rule 21; the `:investigate` clause's `TargetAlive` wiring; the
  `AnnounceShot` registration)
- `lib/werewolf_ash/games/phase/calculations/vote_tally.ex` (rule 21)
- `lib/werewolf_ash/games/player/calculations/` (new: `visible_alive`, if not
  written inline)
- `mobile/schema.graphql`, `mobile/src/gql/*` (regenerated)
- `priv/repo/migrations/` and `priv/resource_snapshots/repo/` (generated)
- `CLAUDE.md` (the rule text above; the owner edits it, coders are refused)

### Existing tests a rule will break

Every command below was run; hits are listed.

`grep -rn "finish_game" test` gives `reactors/resolve_win_test.exs:77,79,85,
104`, `game/changes/resolve_hunter_deadline_test.exs:68`,
`player/policy_test.exs:87,117`. Rule 15 adds a `game_over` row on each
`finish`; none of these read announcements, so they do not break. `:85`
passes `:nobody` and is refused by the Winner enum before any change runs,
so no row.

`grep -rn "ForbiddenField" test` gives `player/policy_test.exs:79,99,113`,
`policy_end_to_end_test.exs:88`, `accounts/user_test.exs:141`. Each reads a
living wolf's or seer's role, or a user's email, never an announced dead
player's, so rule 18 does not touch them. `player/policy_test.exs:102-113`
kills a villager with `update_player!` (never announced, so the reader is
dead, not a role grant) and is unaffected.

`grep -rn "alive: false" test | grep -v "authorize?: false"` gives
`policy_end_to_end_test.exs:58`, `game/policy_test.exs:31`,
`message/visibility_test.exs:22`, `action/policy_test.exs:193,203,214`,
`player/policy_test.exs:22,105`, `author_may_post_test.exs:26`. All kill by
`update_player!`, which is never announced; rules 19-21 change only the
`visible_alive` calculation and the vote-read expression, and the raw `alive`
attribute those tests assert is unchanged (rule 20 keeps it). The vote-policy
tests at `action/policy_test.exs:183-216` read `:vote` rows with dead voters
for a dead or living reader; rule 21 makes an unannounced dead voter's row
visible to a living reader, so any test there whose dead voter comes from
`update_player!` (`:193,203,214`) and expects a living reader NOT to see the
row is stale, since those players are unannounced. The corrected assertion
is: mark the death announced first (or set `death_announced_at` through the
change under test) to keep the "dead voter is dropped" case; add a case for
the unannounced one. These tests belong to 27w.3 and do not exist until it
lands, so the coder confirms by running them.

Rule 21 breaks two existing vote-tally tests (the tests' expectation is
stale, not the rule). Grep: `grep -rn "vote_tally\|VoteTally" test`.
`test/werewolf_ash/games/phase/calculations/vote_tally_test.exs:145-167` (the
`living_view`/`dead_view`/`own_vote_view` test that kills `voter_dead`,
`target_b`, `reader_dead` with `update_player!`, asserts at `:159-162` and the
`dead_view` at `:163-167`) and `test/werewolf_ash/games_test.exs:1209-1290`
(the three tests at `:1209-1256`, `:1237-1256`, `:1258-1290`, killing voters
or targets the same way and asserting a living reader drops them). Those
players are unannounced, so a living reader now still sees them `counts: true`.
Fix: set `death_announced_at` on each player those tests kill (a private
attribute: `Changeset.force_change_attribute` on `Player :update`, in a small
test helper) so the "dropped" cases hold, keep the `dead_view` assertions as
they are (a dead reader's real `counts: false`), and add one case where the
death is unannounced and the living reader sees the vote with `counts: true`.
Also `grep -rn "TargetAlive" test` gives
`action/validations/target_alive_test.exs:21,34,41` (default behaviour, no
option, so unchanged) and the `:investigate` dead-target tests
`action_test.exs:153` (kills with `update_player!`, no landed kill row, still
refused under rule 26).

`grep -rn "end_day\|end_night" test` (files: `games_test.exs`,
`policy_end_to_end_test.exs`, `action_test.exs`,
`game/changes/advance_phase_test.exs`,
`game/changes/open_hunter_window_at_dawn_test.exs`,
`game/changes/open_hunter_window_on_lynch_test.exs`,
`game/changes/resolve_day_vote_test.exs`,
`game/changes/resolve_night_win_test.exs`) now insert one announcement row per
transition, plus a `game_over` on a finish; none reads the table, and every
one that destroys a game passes through rule 1's `on_delete: :delete`.
`policy_end_to_end_test.exs:57-64` ends the day with a
`update_player!`-killed villager: rule 11 sees no new death (`no_lynch`),
so no break.

`grep -rn "destroy_game" test`: `games_test.exs:589`, `message_test.exs:173`
destroy a game; with rule 1's cascade this still succeeds.

`grep -rn "alive" test/werewolf_ash_web`: not yet written for 27w.3; if the
27w.3 GraphQL tests read `alive` of a killed player as a living reader, the
expectation is stale (rule 20), not the rule: use `true` before dawn, `false`
after.

Framework claims: `field_names` covers calculations
(`deps/ash_graphql/lib/resource/resource.ex:2544` reads `field_names[calculation.name]`);
that a calculation renamed to the same GraphQL name as a hidden attribute
compiles is unverified: the coder proves it with the introspection test and
reports if wrong. That `after_action` hooks registered in `end_day` and
`end_night` run in registration order after the `ResolveWin` reactor's own
`finish` is the convention `open_hunter_window_on_lynch.ex` already relies on.
That the reactor's `update :finish` step runs `Game :finish`'s `after_action`
hooks in the same transaction is unverified; the coder proves it with the
mid-night-kill and lynch-win tests.
