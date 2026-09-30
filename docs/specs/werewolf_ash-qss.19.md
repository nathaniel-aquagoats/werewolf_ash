# werewolf_ash-qss.19: Day and night announcements: dawn death report with roles, dusk notice

Implemented in PR #33.

Depends on: werewolf_ash-27w.3

## For the owner

**What changes.** The game now tells everyone what happened, at the moment it
happens. At dawn the village hears who died in the night and what each one
was. At dusk it hears who was lynched and what they were, or that nobody was,
and that night is starting. A hunter's shot is announced at once, and a
finished game announces its winner. A night kill is discoverable at once,
like finding the body (the victim reads as dead to anyone who looks), but
nothing is announced until dawn: only the dawn announcement lists the death
and makes the victim's role public. Players read all of this over
GraphQL with an `announcements` query.

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
4. Scope? — **Decided:** includes GraphQL (`announcements` query); live push stays with 27w.4 (2026-09-29).
5. Are night deaths hidden from the living until dawn? — **Decided:** no
   (2026-09-30, supersedes the 2026-09-28 decision that hid them). A night
   kill is discoverable at once: `alive` reads false to anyone who looks, and
   the victim, being dead, gets the dead's full view at once (the dead see
   everything). But it is not announced until dawn: nothing is pushed or
   announced mid-night, and the dawn announcement lists the death and makes
   the role public. A hunter's shot is unchanged and still announced at once.
   Aliveness, votes and the seer are unchanged from today.
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
   public" (2026-09-29).
10. Does the dawn report appear when nobody died? — **Decided:** yes, with an
    empty list, and the dusk one always (2026-09-29).
11. The shot's time? — **Decided:** the wall clock when the shot lands; dawn
    and dusk use the transition's `now`; `game_over` the wall clock
    (2026-09-29).
12. Order of announcements? — **Decided:** creation order (`inserted_at`),
    with `game_over` always last. Not `announced_at`: a shot uses the wall
    clock while dawn and dusk use the injected `now`, so the two can disagree
    (2026-09-29).
13. Does a shot notice also report an earlier, unannounced night victim? —
    **Decided:** no, only the shot victim; the night victim waits for dawn
    (2026-09-29).

**Rule changes.** Add to CLAUDE.md, under Conventions & Patterns, after "Deaths
are announced":

> - Announcements (owner decisions 2026-09-29, 2026-09-30): every announcement
>   is an `Announcement` row (dawn, dusk, shot, game_over), created by the
>   game's rules inside the transition's own transaction, readable by every
>   seat of the game and by no one else. A night kill is discoverable at once
>   (the victim reads as dead and the dead see everything) but is not
>   announced until dawn; only then does the dawn announcement list the death
>   and make the victim's role public. A lynch is announced at dusk and a
>   hunter's shot at once.

The "Deaths are announced" bullet is unchanged; the dusk lynch reveal it states
is now delivered by the dusk announcement.

## Goal

The village is told what the world did, when it did it. Dawn reports the
night's deaths with their roles; dusk reports the lynch (or that there was
none) and that night begins, or hands over to a `game_over` with the winner
when the lynch ended the game; the hunter's shot is reported the instant it
lands. Every seat of the game, dead included, can read these, outsiders
cannot, and over GraphQL they come in order. A night victim is
discoverable as dead at once, but nothing announces the death, and their role
stays hidden from living players, until the dawn report names it.

## Rules

Terms: "announced" means the player's private `death_announced_at` is
non-nil. "Unannounced death" is `alive == false` and not announced (in practice a
night kill's victim before dawn). `alive` is never hidden: a night death is
discoverable at once but only announced at dawn (card decision 5). All creation below uses `authorize?: false`, inside the
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
    `update_player`) is still hidden. The existing grants are unchanged: the
    victim themselves, being dead, already read every role.
19. A wolf kill announces nothing. After a wolf kill and before `end_night`,
    no announcement row exists for it (`announcements` has no entry naming the
    victim), while every reader's `players { alive }` already shows the victim `false`
    (the stored value, exactly as today), and a living villager's read of the
    victim's role is still forbidden.

### GraphQL

20. `Announcement` gets `AshGraphql.Resource` (type `:announcement`), the
    embedded `Death` gets type `:announced_death`. A new read action
    `:in_game` with a required `game_id` argument backs the list query
    `announcements(gameId)`, sorted per rule 5, with no pagination. It applies
    rule 3 by policy: a non-member or an unknown id gets `[]`, no `errors`,
    and no token gets `[]`. No mutation is added for announcements.
21. `Game` gains no field for announcements; a client asks `announcements`.

### Finish

22. `Game :finish` gains `require_atomic? false`, because the `game_over`
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
- Hiding a night death (aliveness, votes, the seer's options, chat): decided
  against on 2026-09-30; `alive`, the Action read policy, `VoteTally` and
  `TargetAlive` are untouched.
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
- `Player` field policy (`role`) — a living villager forbidden before, allowed
  after an announcement, for a lynched, killed, and shot player; a
  `update_player`-killed one stays forbidden.
- GraphQL: `announcements(gameId)` as a member, as a dead member, as an
  outsider (`[]`), with no token (`[]`); after a night kill and before dawn,
  `players { alive }` shows the victim `false` to a villager, the victim and a
  wolf, `role` of the victim is forbidden to the villager before dawn and
  readable after, and `announcements` holds no entry naming the victim;
  introspection: `deathAnnouncedAt` is absent from the schema.

End to end: through the code interface, a started game plays a night with a
wolf kill, the villager reads the victim dead at once with the role hidden and
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
- `lib/werewolf_ash/games/player.ex` (attribute, field policy)
- `lib/werewolf_ash/games/announcement.ex`,
  `lib/werewolf_ash/games/announcement/*.ex` (new: embedded Death, kind and
  cause enums)
- `lib/werewolf_ash/games/game/changes/` (new: dawn, dusk, game over)
- `lib/werewolf_ash/games/action/changes/announce_shot.ex` (new; `apply_shot.ex`
  itself is not changed)
- `lib/werewolf_ash/games/announcer.ex` (new)
- `lib/werewolf_ash/games/action.ex` (the `AnnounceShot` registration only)
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
`update_player!`, which is never announced. No rule changes `alive`, the
Action read policy, `VoteTally` or `TargetAlive`, so none of these, nor
`vote_tally_test.exs`, `games_test.exs`' tally tests or
`action/validations/target_alive_test.exs`, is affected.

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

Framework claims: that `after_action` hooks registered in `end_day` and
`end_night` run in registration order after the `ResolveWin` reactor's own
`finish` is the convention `open_hunter_window_on_lynch.ex` already relies on.
That the reactor's `update :finish` step runs `Game :finish`'s `after_action`
hooks in the same transaction is unverified; the coder proves it with the
mid-night-kill and lynch-win tests.
