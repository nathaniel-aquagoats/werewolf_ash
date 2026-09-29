# werewolf_ash-qss.7: Hunter: pending state, 1h window, random fallback

Depends on: none

## For the owner

**What changes.** When the hunter is lynched at dusk, and that lynch does not
end the game, the hunter gets one hour to shoot anyone still alive. A hunter
killed by the wolves at night is just dead until dawn; the hour opens with
the new day, again only if the game is not over. The game does not pause
during the hour. If the hour runs out, a random living player is shot
instead. The shot kills at once, protection cannot stop it, and the win
check runs after it.

**Decisions.**
1. Does the game keep running during the hunter's hour? — **Decided:** yes
   (2026-09-28). `Game.state` stays day/night, there is no `hunter_pending`
   state and no remembered or resumed transition. The game gets a
   pending-hunter pointer and a deadline (death time + 1h); the shot is
   recorded against whatever phase is open when it lands.
2. What if the hunter's death itself ends the game? — **Decided:** the game
   finishes and the hunter gets no shot (2026-09-28).
3. May the hunter pass? — **Decided:** no, the shot is mandatory. Either
   they shoot within the hour or a random living player is shot at the
   deadline (2026-09-28).
4. Who can the random fallback hit? — **Decided:** any living player,
   uniformly, wolf or not (2026-09-28).
5. Does bodyguard protection stop the hunter's shot? — **Decided:** no. It
   guards only against the pack's kill; the shot always kills a living
   target (2026-09-28).

6. When does the hour start? (round 2, supersedes the draft) — **Decided:**
   a hunter lynched at dusk gets the hour at once (deadline = dusk + 1h). A
   hunter killed by the wolves is dead until dawn; the hour opens when the
   night ends (deadline = dawn + 1h). In both cases the win check runs first
   and a finished game opens no window, including the dawn win check.
7. Who may see the window? — **Decided:** every seated player. It only ever
   opens at a public moment (a lynch at dusk, the dawn announcement), so no
   field policy is added.
8. Is a lynched player's role revealed at dusk? — **Decided:** yes, every
   lynch reveals the role at dusk. This bead does not implement it; it
   belongs to werewolf_ash-qss.19's dusk notice.
9. Does the random fallback leave a record? — **Decided:** yes, a `:shoot`
   row (the hunter as actor, in the open phase, flagged as the fallback),
   like a chosen shot.
10. What does the deadline action do too early or twice? — **Decided:** a
    silent no-op, also when nothing is pending or the game is finished.

**Rule changes.** (1) Every lynch reveals the lynched player's role at dusk
(decision 8; implemented by werewolf_ash-qss.19, not here). (2) CLAUDE.md,
architecture bullet for `lib/werewolf_ash/games`, replace "`Game.state` is
one of `lobby | day | night | hunter_pending | finished`" with:

> `Game.state` is one of `lobby | day | night | finished`; an open hunter
> window is `Game.pending_hunter_id` plus `Game.hunter_deadline_at`, not a
> state, and every seated player can read both

(3) In "Rules decisions already made", replace "hunter gets a 1h window after
death then a random target" with:

> a hunter lynched at dusk gets a 1h window at once; a hunter killed by the
> wolves gets it at dawn (only if the game is not over by then); the game
> keeps running during the window, the shot is mandatory, and at the deadline
> a uniformly random living player is shot instead; the shot kills
> immediately, ignores the bodyguard, and is followed by the win check. The
> window opens only at a public moment, so every seated player may see it

## Goal

A hunter lynched at dusk, or killed in the night and then revealed at dawn, while the game goes on holds a one-hour window in which
they, and only they, may shoot one living player. The window is a pointer on
the game, not a phase: the day or night in progress continues untouched. The
shot, or at the deadline a random living player, dies immediately and the
win check decides whether the game is over. Once the window is used or the
game finishes, no shot remains.

## Rules

Terminology: the "window" is `Game.pending_hunter_id` non-nil together with
`Game.hunter_deadline_at`; they are set and cleared together.

1. `Game` gains `pending_hunter_id` (uuid, nil by default, a plain attribute,
   no foreign key) and `hunter_deadline_at` (`utc_datetime_usec`, nil by
   default). A new game has both nil. Both are `public? true` (rule 23). They are written only with
   `force_change_attribute` inside the changes of this bead and are never
   added to any action's `accept` list, `:update` included, so no caller
   can set a window by hand.
2. `:hunter_pending` is removed from `Game`'s `@states`, from
   `state_machine`'s `extra_states`, and from the `:finish` transition's
   `from:` list (which becomes `[:day, :night]`). `Game.state` can no longer
   be set to `:hunter_pending`.
3. Lynch path: when `end_day` lynches the player dealt `:hunter` and the
   dusk win check returns `:continue`, the game (state `:night`, as today)
   gets `pending_hunter_id` = the hunter's player id and `hunter_deadline_at`
   = `end_day`'s `now` argument + 1 hour. `phase_ends_at`, the night phase
   and the rest of `end_day` are unchanged.
4. Lynch path, game ends: when the lynch of the hunter makes the win check
   decide a winner, the game is finished as today, the pointer and deadline
   stay nil and no window ever opens.
5. Lynch path: a lynch of a non-hunter, or no lynch, opens no window.
6. (withdrawn) The kill path opens no window: a landed `:kill` on the
   hunter is a plain death, and the `:kill` action gains no `now` argument
   and no new change. `ApplyKill` and `ResolveKillWin` are unchanged.
7. Dawn path: when `end_night` closes a night and, after `ResolveNightWin`'s
   dawn win check, the game is still `:day`, and the game's dealt hunter is
   dead, has no `:shoot` `Action` row in the game (any phase) and the game
   has no open window, then the game gets `pending_hunter_id` = the
   hunter's player id and `hunter_deadline_at` = `end_night`'s `now`
   argument + 1 hour. This is the mechanism by which `end_night` knows the
   hunter died in the night just closed. It cannot reopen a spent window: a
   window closes only by a shot (chosen or fallback, both leave a `:shoot`
   row) or by the game finishing (`end_night` never runs on a finished
   game), and a still-open window is excluded by its non-nil pointer. The
   hunter's only ways to die are the lynch (rule 3 already opened the
   window) and the pack's kill.
8. Dawn path, game ends: when the dawn win check finishes the game, no
   window opens (pointer and deadline nil). A night with no hunter death,
   a living hunter, or a game with no hunter dealt opens no window.
9. The win check always runs before a window would open, and the window
   opens only when the game is still `:day`/`:night` after it. A game whose
   state is `:finished` never has a window opened on it. Rule 7's window
   change is registered after `ResolveNightWin` in `end_night`.
10. `ShootRequiresPendingHunter` passes only when the actor's own player id
    equals the game's `pending_hunter_id` (the game being the one the actor
    is seated in). It no longer reads `Game.state` and no longer looks at the
    actor's role. It fails, on `:actor_id`, when the pointer is nil, names
    someone else, or the actor is not a player.
11. `:shoot` on `:create` also runs `TargetAlive` (a dead or unknown target
    fails on `:target_id`). `ActorAndTargetInGame` already runs on every
    type. Reuse both as they are; no new validation module is written for
    target rules. `ActorAlive` still does not run for `:shoot`. No
    validation is added for which phase the shot's `phase_id` names or
    whether it is still open: the shot is recorded against whatever phase
    the caller names in the game.
12. A landed `:shoot` kills its target immediately (`alive: false`) and
    records `result: %{"killed" => true}` on the action row. Bodyguard
    protection, in any form, does not change this: `ApplyKill`'s protection
    lookup is not consulted, and a target the bodyguard protected dies.
13. After a landed shot, in the same transaction, the win check
    (`ResolveWin`) runs; if a side has won the game is finished
    (`state: :finished`, `winner` set) right there, with the phase left as
    it is.
14. After a landed shot `pending_hunter_id` and `hunter_deadline_at` are
    nil, whether or not the game finished.
15. A second `:shoot` by the same hunter is refused (with the pointer cleared
    the rule-10 validation fails on `:actor_id`), and refused again for any
    other player.
16. New Game update action `resolve_hunter_deadline` with a `now` argument
    (`utc_datetime_usec`, default `DateTime.utc_now/0`) and an optional
    integer `pick` argument for deterministic tests. When a window is open
    and `now >= hunter_deadline_at`, it shoots one living player of the game
    chosen uniformly at random from all living players regardless of role,
    with that player's `alive` set false. Living players come from the
    existing `Games.list_living_players/1` (`Player :living_in_game`), no
    new query, ordered by id; with `pick` given, the target is that list at
    index `pick` modulo its length; with `pick` nil the index is drawn
    uniformly at random. The dead hunter is not living and cannot be chosen.
17. `resolve_hunter_deadline`'s shot is treated exactly like a landed shot
    for rules 12-14: bodyguard protection is ignored, the win check runs
    after it, the game finishes if a side won, and the pointer and deadline
    are cleared. It also records a `:shoot` `Action` row: actor = the
    hunter, target = the shot player, phase = the game's open phase, and
    `result` = `%{"killed" => true, "fallback" => true}` (a chosen shot's
    result has no `"fallback"` key). It may be created through the same
    `:create` path as a chosen shot; whichever route, the row exists.
18. `resolve_hunter_deadline` is a no-op that succeeds, changing nothing
    (no death, pointer and deadline untouched), when no window is open
    (pointer nil, including after a shot, after an earlier deadline, and on
    a finished game) or when `now < hunter_deadline_at`. Running it twice
    with the same arguments therefore shoots at most one player. It never
    reads the wall clock except through the defaulted `now` argument, and
    the game's own phase timers are never consulted.
19. Finishing a game by any route (the `finish` action) clears
    `pending_hunter_id` and `hunter_deadline_at`, so a window cannot
    outlive the game. After that a `:shoot` is refused by rule 10.
20. Every Reactor run added or changed by this bead from inside an action
    runs with `async?: false`, as the existing `ResolveWin` runs do.
21. Every new Game action is named in `Game`'s policies (`authorize_if
    always()`, the same as `end_day`/`finish`) so the `Ash.Policy.Authorizer`
    default-deny does not refuse it. `:shoot` keeps the existing `:create`
    policy (actor must be the caller's own seat). The kill's own policy is
    unchanged.
22. The qss.21 interaction holds: a hunter lynched at dusk who shoots the
    living bodyguard during the night, before the pack's kill, cancels that
    night's protection, so a kill on the player the bodyguard had protected
    that day lands. No night-start lock is added; this needs no code beyond
    rule 12 and `ApplyKill`'s existing `protector_alive?` check.
23. Read visibility (owner decision 7): `pending_hunter_id` and
    `hunter_deadline_at` are readable by every player seated in the game
    (the existing Game read policy), no narrower and no wider. No field
    policy is added: the window only opens at a public moment (a lynch at
    dusk, the dawn announcement), so nothing is revealed early. That
    every lynch reveals the lynched role at dusk is not implemented here
    (qss.19).
24. The shot's `:shoot` `Action` row stays visible to every seated reader,
    as today; the Action read policy is unchanged.

## Out of scope

- The AshOban trigger that calls `resolve_hunter_deadline` when
  `hunter_deadline_at` passes, and the `end_day`/`end_night` triggers:
  werewolf_ash-qss.9. Here the action exists and is called by hand.
- GraphQL exposure of the new attributes, `:shoot`, or
  `resolve_hunter_deadline`, and the mobile UI: not in this bead.
- Announcing the window or the shot in chat or in the day/night death
  announcements: no bead owns it yet.
- A pass/skip option for the hunter (decision 3), a hunter who can shoot
  while alive, a second hunter, and a retargetable shot.
- Requiring the shot's `phase_id` to name the open phase (rule 11 says it
  does not).
- A foreign key from `pending_hunter_id` to players, or a `belongs_to`.
- Changes to `ResolveLynch`'s result contract or inputs. Whether the hunter
  just died is worked out by the caller (for example: the hunter's `alive`
  before versus after the lynch), not by changing the reactor's input.
- Revealing a lynched player's role at dusk in general (decision 8), and the
  dusk notice: werewolf_ash-qss.19.
- Any future GraphQL exposure of `resolve_hunter_deadline` must not accept
  `pick`; it is a test hook only (that exposure is not this bead).
- Rewriting the full-game rules suite: werewolf_ash-qss.10.
- Editing older specs that mention `hunter_pending` (qss.5, qss.6, qss.18,
  qss.21, 27w.2); specs are not edited after merging.

## Acceptance

- `Game` create/read: `pending_hunter_id` and `hunter_deadline_at` are nil on
  a new game; `state` rejects `:hunter_pending`.
- `Game.resolve_hunter_deadline/2` (code interface, e.g.
  `Games.resolve_hunter_deadline/2`): shoots the picked living player once
  `now >= hunter_deadline_at`; picks uniformly over all living players
  (with `pick`, test the modulo mapping and that wolves are eligible); no-op
  before the deadline, with nothing pending, on a finished game, and on a
  second run; records a `:shoot` row flagged `"fallback"`; runs the win
  check afterwards; clears the pointer.
- `ShootRequiresPendingHunter.validate/3` (rewritten test file): passes for
  the player named by the pointer; fails on `:actor_id` for a different
  player, for a nil pointer, and for an actor that is not a player.
- `Games.create_action/5` with `:shoot`: kills the target immediately; a
  protected target still dies; win check runs and can finish the game; a
  dead target fails on `:target_id`; a target seated in another game fails
  on `:target_id`; pointer and deadline cleared; a second shot refused.
- The new change that applies a landed shot (name at the coder's choice,
  registered on `:create` only for `:shoot`): direct unit test of its own
  contract (kill, result, win check, clear).
- Each new change module gets its own direct unit test on its own
  contract (names at the coder's choice): the shot-applying change; the
  change opening the window on the lynch path (only for the dealt hunter,
  only when the win check continued, deadline = `now` + 1h); the change
  opening the window at dawn (rule 7: dead hunter with no `:shoot` row and
  no window opens one, deadline = `end_night`'s `now` + 1h; does not open
  when a `:shoot` row exists, when a window is already open, when the game
  finished, or when the hunter is alive); the deadline change (rule 16).
- `Games.create_kill_action/4,5`: unchanged; a landed kill on the hunter is
  a plain death opening no window (rule 6).
- `Games.end_day/2` with a lynched hunter: window opens (pointer, deadline),
  state stays `:night`, next phase opens as before; with the lynch of the
  hunter ending the game: finished, no window.
- `Games.end_night/2`: a hunter killed in the night gets the window at
  dawn (state `:day`); a hunter whose dusk window was already used by a
  chosen shot or by the fallback never gets a second window at the next
  dawn; a dawn win finishes the game with no window.
- `Games.finish_game/2`: clears an open window.
- Direct tests of `TargetAlive.validate/3`'s new wiring are covered by the
  `:shoot` create test (validation module itself unchanged).
- End to end (dusk path): started game, hunter lynched at dusk (window opens, state
  `:night`); a seer investigation and the hunter's own `:shoot` both succeed
  in the same night; the shot kills the bodyguard; the pack's kill on the
  player the bodyguard had protected that day lands (rule 22); then a second
  game where nobody shoots and `resolve_hunter_deadline` with `now` past the
  deadline and a fixed `pick` kills exactly the expected player and leaves
  a fallback-flagged `:shoot` row. Dawn path: the wolves kill the hunter, the
  hunter cannot shoot before dawn (pointer nil, `:shoot` refused),
  `end_night` opens the window, the hunter shoots, and a second
  `end_night` opens nothing.

## Touches

Advisory: the coder may deviate. Files the rules will probably reach:

- `lib/werewolf_ash/games/game.ex` (attributes, `@states`, `extra_states`,
  `:finish` transition, new action, policy, `finish` clearing the window)
- `lib/werewolf_ash/games.ex` (code interface entries)
- `lib/werewolf_ash/games/action.ex` (`:create` wiring: `TargetAlive` for
  `:shoot`, new change; moduledoc; the `:kill` action is not changed)
- `lib/werewolf_ash/games/action/validations/shoot_requires_pending_hunter.ex`
- `lib/werewolf_ash/games/action/validations/target_alive.ex` (moduledoc)
- `lib/werewolf_ash/games/action/validations/actor_alive.ex` (moduledoc)
- `lib/werewolf_ash/games/action/changes/` (new: shot and window-opening
  changes)
- `lib/werewolf_ash/games/game/changes/resolve_day_vote.ex`
- `lib/werewolf_ash/games/game/changes/resolve_night_win.ex` (only if the
  dawn window opening is placed there; else a new change after it in
  `end_night`)
- `lib/werewolf_ash/games/game/changes/` (new: deadline change)
- `priv/repo/migrations/` and `priv/resource_snapshots/repo/games/`
  (generated by `mix ash.codegen`)
- `CLAUDE.md` (rule text above; the owner edits it, coders are refused)

Migration: needed for the two new columns (`mix ash.codegen
add_hunter_window_to_games`). Removing `:hunter_pending` needs none: `state`
is a `text` column and `one_of: @states` is an application constraint only
(`priv/resource_snapshots/repo/games/20260913034433.json:96-97`, `"type":
"text"`, no DB check constraint).

### Existing tests a rule will break

Grep run: `grep -rn "hunter_pending\|force_state" test`, and `grep -rn
"hunter" test | grep -v shoot_requires`.

`hunter_pending` (every hit is stale; the rule is not):

- `test/werewolf_ash/games/action_test.exs:99` (`force_state(game,
  :hunter_pending)` in "the pending hunter, already dead, can shoot"),
  `:289` ("rejects a shot from anyone but the pending hunter"), `:1120`
  ("hunter path"). `force_state/2` defined at `:44` forces `state`, which
  now fails the constraint. Replace with setting `pending_hunter_id` (and
  `hunter_deadline_at`) on the game to `p.hunter.id`, via
  `Changeset.force_change_attribute` on `:update` or via a helper; state
  stays `:day`. At `:289` the pointer names the hunter and the villager's
  shot must still fail on `:actor_id`. The tests at `:99` and `:1120` also
  need a living target to shoot: they use `p.villager` (alive), unchanged.
- `test/werewolf_ash/games/action/validations/shoot_requires_pending_hunter_test.exs:19-30,
  :33-45`: `force_state(game, :hunter_pending)` at `:23`, `:36`, and the
  test named "fails for a hunter actor whose game is in any other state"
  (`:48-58`). Stale: rewrite to set the pointer; "any other state" becomes
  "fails when the pointer is nil"; add "fails when the pointer names another
  player".

Tests that assert hunter-death behaviour the rules change (title stale;
assertion on `state` still holds):

- `test/werewolf_ash/games_test.exs:489-500` "a lynched hunter dies like any
  other target: no hunter window, straight to night (rule 11)". Stale: the
  hunter now gets a window. Corrected assertion: the game is still `:night`
  and `pending_hunter_id == p.hunter.id` with `hunter_deadline_at` = the
  `now` passed + 1h. Rename the test.
- `test/werewolf_ash/games/action_test.exs:766-777` "a landed, non-decisive
  kill on the dealt hunter is a plain death (qss.6 rule 5)": still true
  under rule 6 (no window at the kill); unaffected.
- `test/werewolf_ash/games/action_test.exs:1011-1020` kills `p.hunter` and
  asserts only the kill result and `alive`; unaffected by rule 6. If that
  test goes on to call `end_night`, a dawn window may now open (rule 7);
  nothing there reads the pointer, so it still passes.
- The remaining `hunter` hits (`games_test.exs:430,781,910,939,992`,
  `role_assignment_test.exs`, `composition_fits_at_cap_test.exs:18`,
  `role_composition_fits_test.exs:66`, `deal_roles_test.exs:27`,
  `game_not_full_test.exs:72`, `check_win_test.exs:39`, `action_test.exs`
  lines `:117,153-174,354-357,738,808,864,1072-1109`) concern role dealing,
  the `hunter_enabled` setting, or a hunter being marked dead by
  `update_player!` (which bypasses the window rules 3-9 entirely) or voted
  or investigated as a target; none goes through `end_day`'s lynch or
  `:kill` on the hunter with a window assertion, so rules 3-9 leave them
  unaffected. `action_test.exs:1072-1109` votes/protects `p.hunter` and
  never kills them.
- `end_night` callers (grep `grep -rn "end_night" test`):
  `games_test.exs:228,260,343,352`; `action_test.exs:212,440,845,867,961,
  975,1093`. Rule 7 now opens a dawn window whenever the dealt hunter is
  dead with no `:shoot` row. Only `action_test.exs:864` reaches `end_night`
  with the hunter dead, and that game finishes at dawn, so no window opens;
  every other caller above has a living hunter. (`:738` and `:808` are
  kill-aftermath tests and never call `end_night`.) The coder should confirm
  by running them.
- Other `force_state` definitions
  (`resolve_lynch_test.exs:14`, `resolve_night_win_test.exs:11`,
  `resolve_day_vote_test.exs:11`, `resolve_kill_win_test.exs:12`) force
  `:day`/`:night` only: unaffected by rule 2.
- Callers of `Game.finish` are unaffected by rule 19 apart from clearing two
  already-nil fields: `lib/werewolf_ash/games/reactors/resolve_win.ex`
  (`update :finish`) and `Games.finish_game/2`.
- Docs/comments naming `hunter_pending`: `game.ex:12,38,48,54` (fixed by
  rule 2); `shoot_requires_pending_hunter.ex:4-11` (rewritten),
  `CLAUDE.md:94`.

Framework claims are limited to: AshStateMachine `extra_states` and
`transition` lists are compile-time only (unverified beyond the snapshot
evidence above; the coder should confirm `mix ash.codegen --check` is clean).
