# werewolf_ash-qss.20: Tighten two qss.4 test assertions flagged in PR #5 review

Depends on: none

## For the owner

**What changes.** Two existing tests get tighter so they actually check what they claim to. Test quality only; players notice nothing.

**Decisions for you.** None.

**Rule changes.** None.

## Goal

The two weak assertions in `test/werewolf_ash/games/action_test.exs` that PR
#5's review flagged now pin the property they claim to, instead of a proxy
that passes even when that property is false. No production code changes.

## Rules

1. In the test `"a second kill for the same phase always fails (rule 11)"`
   (currently lines 254-271), the line `assert Games.get_action!(first.id).id
   == first.id` is replaced with assertions on the re-read action's
   `target_id` and `result`, each equal to `first`'s own `target_id` and
   `result` — mirroring the pattern already used at lines 177-179 for the
   analogous rule-9 test.
2. In `started_game/0` (currently lines 18-29), after building `players` via
   `Map.new(&{&1.role, &1})`, add `assert map_size(players) == 5` so a future
   change to the game's role distribution that hands out a duplicate role
   (silently collapsing two players into one map key) fails at the helper
   instead of later as an unrelated `KeyError` or a wrong-role assertion.
3. (withdrawn — a scope statement, not a rule any test could fail; it is
   covered by Out of scope.)

## Out of scope

- Any production code in `lib/` — this bead is test assertions only, per its
  `Done:` line ("Test quality only; no behaviour change").
- The other beads being spec'd in parallel (qss.5, qss.6, qss.18, qss.14).
  In particular, qss.14 (making role distribution configurable) is exactly
  the future change rule 2's assertion is meant to catch — this bead only
  adds the guard, it does not touch role dealing itself.
- Any other assertion in `action_test.exs` not named in the two rules above,
  even if it looks similarly weak.

## Acceptance

- `test/werewolf_ash/games/action_test.exs`, `"a second kill for the same
  phase always fails (rule 11)"`: prove the strengthened assertions are
  load-bearing by, in a scratch copy of the test, changing the first kill's
  row after the rejected second attempt and before the re-read (for example
  updating its `result` directly). The new `target_id` / `result` assertions
  must then fail, where the old `Games.get_action!(first.id).id == first.id`
  would still pass, since that line only proves the row exists.
- `test/werewolf_ash/games/action_test.exs`, `started_game/0`: prove
  `assert map_size(players) == 5` is load-bearing by, in a scratch copy,
  making `RoleAssignment.composition/1` hand out a duplicate role (for example
  two `:seer`). `Map.new` then silently drops a player, `map_size(players)` is
  4, and the new assertion fails, where the old helper would have produced a
  confusing failure later or none at all.
- End to end: `mix test test/werewolf_ash/games/action_test.exs` passes in
  full, unchanged in test count, with both edited assertions in place.

## Touches

Advisory only.

- `test/werewolf_ash/games/action_test.exs` — the only file this bead edits
  (lines ~18-29 and ~254-271 as of this spec; re-check before editing since
  qss.4 test edits from other beads may shift them).
