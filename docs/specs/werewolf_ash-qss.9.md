# werewolf_ash-qss.9: AshOban scheduler for phase ends and hunter deadline

Implemented in PR #32.

Depends on: none

## For the owner

**What changes.** Days and nights now end by themselves, and an unused hunter
hour expires by itself, at the exact moment each is due. If the server is down
for a while, it catches up on restart, replaying each missed phase in order.
Actions submitted a moment before the server gets round to ending a phase still
count. A game that ends stops its pending timers.

**Decisions.**
1. Downtime: what happens to boundaries missed while the server was off? —
   **Decided:** replayed in order, one phase per job, each using the recorded
   boundary as its `now` (2026-09-29).
2. Is there a strict cut-off at the boundary? — **Decided:** no. Actions
   submitted before the transition actually runs count; no action validation
   changes; strict cut-offs stay with qss.15 (2026-09-29).
3. How is it scheduled? — **Decided:** no cron and no sweeper. Each boundary
   gets exactly one Oban job scheduled for its exact time, enqueued in the
   transaction that opens the phase or hunter window (2026-09-29 revision).
4. Retries? — **Decided:** effectively unlimited (`max_attempts` 1_000_000),
   with this wait after each failed attempt: 30 seconds after the first
   failure, 1 minute after the second, 5 minutes after the third, and 10
   minutes after every later failure, forever. No `on_error` action, no new
   attribute (2026-09-29).
5. AshOban trigger or plain worker? — **Decided:** AshOban triggers on `Game`
   with no scheduler (no cron), enqueued with `AshOban.run_trigger` at the
   exact time. Dedicated Game actions take the recorded time, lock the row and
   check the exact boundary. A stale job whose `where` no longer matches
   becomes a cancelled job, which is acceptable (2026-09-29).
6. Lifeline `rescue_after` — **Decided:** 5 minutes (was 2h) (2026-09-29).
7. Ordering during replay — **Decided:** it goes both ways. A hunter job waits
   while an earlier phase boundary is unprocessed, and a phase job waits while
   the hunter's deadline is strictly earlier than its own time and still
   unprocessed. The two can never both hold. The `:game_clock` queue's
   concurrency is set explicitly (2026-09-29).
8. Do games already in play need a backfill job? — **Decided:** no. No
   deployment exists, so no live game predates this bead; a game started
   before this lands never ends its phase, so restart it (2026-09-29).
9. What happens to a job made stale by the game ending or the hunter shooting?
   — **Decided:** it is cancelled, not left to no-op. Finishing a game by any
   route cancels that game's pending phase and hunter jobs; a hunter shot
   (chosen or fallback) cancels the pending hunter job; both in the same
   transaction (2026-09-29, reverses the earlier "leave it").
10. How many jobs of the `:game_clock` queue may run at once? —
    **Decided:** 10, the same as the other queues (2026-09-29). The ordering
    rules and the per-game row lock make any concurrency safe.
11. Does cancelling on finish or shot also cancel the job that is running right
    now (the phase job whose own transition ended the game, or the hunter job
    whose fallback shot ended the window)? — **Decided:** no (2026-09-29). Only jobs not
    yet started (available, scheduled, retryable) are cancelled; the running
    one completes normally instead of being killed mid-transaction.

**Rule changes.** Two edits to CLAUDE.md.

(1) Architecture, the Reactor sagas bullet: replace "AshOban triggers on `Game`
fire them when `phase_ends_at`/`hunter_deadline_at` pass" with:

> AshOban triggers on `Game` (no cron: each is enqueued for its exact time
> when a phase or hunter window opens) fire them at
> `phase_ends_at`/`hunter_deadline_at`

(2) Conventions, after the Oban bullet, add:

> - Game clock (owner decisions 2026-09-29): a phase end and a hunter deadline
>   are each one exact-time Oban job (`scheduled_at` the recorded boundary),
>   enqueued in the transaction that opens the phase or window; there is no
>   cron and no sweeper. The job uses the recorded boundary as the
>   transition's `now`, never the wall clock. Missed boundaries after downtime
>   are replayed in order, one phase per job, and a phase job and a hunter job
>   for one game wait for each other so replay stays chronological. Every run
>   locks the game row and re-checks, so a repeated job is a silent no-op.
>   Finishing a game, or a hunter shot, cancels the jobs it makes stale, in the
>   same transaction. Retries are effectively unlimited; the wait after
>   failures is 30 s, 1 min, 5 min, then 10 min forever. No action validation
>   enforces a cut-off at the boundary. In tests, drain with a bounded
>   `with_scheduled` cutoff plus `with_recursion: true`, never a bare `true`.

## Goal

Every day and night ends on its own at its recorded boundary, and every
hunter window that nobody uses is closed by the random fallback shot at its
deadline, with no one calling `end_day`, `end_night` or
`resolve_hunter_deadline` by hand. Each transition happens as of the recorded
boundary, not the moment the server got to it, so lag never shifts later
phases, and a server that was down replays every missed boundary in order on
restart. A job that runs twice, late, or for a game that has moved on or
finished does nothing and never creates an extra phase, and a game that ends
leaves no pending timer behind.

## Rules

Terminology: two AshOban triggers on `Game`, both with `scheduler_cron false`
(no scheduler module, no cron entry), both on queue `:game_clock`: `:end_phase`
(action `:end_phase_on_schedule`) and `:hunter_deadline` (action
`:hunter_deadline_on_schedule`). A "phase job" and a "hunter job" are jobs of
each. `WerewolfAsh.Games.Game.ScheduledJobs` is a new plain module holding the
enqueue and cancel helpers. "Recorded time" is `phase_ends_at` for a phase job
and `hunter_deadline_at` for a hunter job, passed to the action as the
`at` argument.

1. `Game` gains the `AshOban` extension and an `oban` section with the two
   triggers. Each sets `scheduler_cron false`, `max_attempts: 1_000_000`, an
   explicit `worker_module_name`, `lock_for_update? false` (the action locks
   the row itself, rule 26), no `on_error`, and the custom `backoff` of rule
   15. `:game_clock` is listed in `config/config.exs` `queues`, with an
   explicit concurrency of 10 (decision 10). No cron entry, no
   `scheduler_cron` string and no sweeper is added.
2. `:end_phase` has `where expr(state in [:day, :night])`. `:hunter_deadline`
   has `where expr(state in [:day, :night] and not is_nil(pending_hunter_id))`.
   A job whose game no longer matches its `where` is cancelled by AshOban
   (`{:cancel, :trigger_no_longer_applies}`), which is acceptable.
3. `ScheduledJobs.schedule_phase_end/1`, given a game whose `phase_ends_at` is
   set, enqueues one `:end_phase` job via `AshOban.run_trigger(game,
   :end_phase, scheduled_at: phase_ends_at, action_arguments: %{at:
   iso8601(phase_ends_at)})`. The `at` value is an ISO8601 string.
4. `ScheduledJobs.schedule_hunter_deadline/1`, given a game whose
   `hunter_deadline_at` is set, enqueues one `:hunter_deadline` job the same
   way, `scheduled_at` = `hunter_deadline_at`.
5. `Game.Changes.AdvancePhase` calls `schedule_phase_end/1` in its existing
   `after_action` hook with the game as written (state and `phase_ends_at`
   set), inside the action's transaction. It is the only place a phase job is
   enqueued, so `start`, `end_day` and `end_night` each leave one job for the
   phase they open. An enqueue failure fails the action and rolls the
   transition back.
6. `Game.HunterWindow.open/4` calls `schedule_hunter_deadline/1` with the game
   returned by its update. It is the only place a hunter job is enqueued, so
   the lynch window (`OpenHunterWindowOnLynch`) and the dawn window
   (`OpenHunterWindowAtDawn`) each leave one job. An enqueue failure is
   returned as `{:error, _}` from `open/4`. `open/4` enqueues on any game it is
   given, including a lobby game (as `hunter_window_test.exs:17-21` does); that
   job is harmless because of rule 12. `clear/2` and `resolve_hunter_deadline`
   enqueue nothing.
7. Lobby games are never scheduled: creating a game, updating settings and
   `finish` enqueue nothing. A phase job or hunter job that somehow runs for a
   `:lobby` game is a no-op (rules 9 and 12).
8. A boundary already in the past when its phase or window opens gets a job
   with that past `scheduled_at`, which Oban treats as due at once. Replaying
   one boundary therefore enqueues the next, in order, until the game catches
   up.
9. New Game update action `:end_phase_on_schedule`, argument `at`
   (`utc_datetime_usec`, `allow_nil? false`, no default), `accept []`,
   `require_atomic? false`. It changes nothing and succeeds (a silent no-op)
   unless, on the freshly read locked game, `state` is `:day` or `:night` and
   `DateTime.compare(phase_ends_at, at) == :eq`. This covers a `:lobby` or
   `:finished` game (even with `phase_ends_at` still set), and a job left from
   an earlier phase, which must not end a later phase early.
10. When rule 9 passes and rule 20 does not snooze, `:end_phase_on_schedule`
    runs `end_day` (state `:day`) or `end_night` (state `:night`) with `now` =
    `at`, never `DateTime.utc_now/0`. The whole thing is one transaction. The
    action's result is the game as advanced (the new phase, the next
    `phase_ends_at`). Running it twice with the same `at` opens one new
    `Phase`: the second run sees a different `phase_ends_at` and is a no-op.
11. New Game update action `:hunter_deadline_on_schedule`, argument `at` as in
    rule 9, `accept []`, `require_atomic? false`. On the freshly read locked
    game it acts only if `state` is `:day` or `:night`, `pending_hunter_id` is
    set and `hunter_deadline_at` equals `at` (rule 12 otherwise). If a phase
    boundary is still unprocessed, meaning `phase_ends_at <= at`, it changes
    nothing and returns AshOban's snooze error for 30 seconds
    (`AshOban.Errors.SnoozeJob`, the worker returns `{:snooze, 30}`, no
    attempt consumed). The snooze error must be the action's only error
    (`check_for_oban_return` unwraps a single error only,
    `ash_oban.ex:1357-1371`). Otherwise it runs the `resolve_hunter_deadline` behaviour
    with `now` = `at` and never `pick`.
12. `:hunter_deadline_on_schedule` is a silent no-op that succeeds when the
    game is `:lobby`/`:finished`, no window is open (pointer nil, after a shot
    or on a finished game), or `hunter_deadline_at` differs from `at`.
13. When the transition inside rule 10, or the shot inside rule 11, returns an
    error or raises, the transaction rolls back (no partial transition remains)
    and the job fails, so Oban retries it.
14. Scheduling a phase job while the previous phase job is still executing is
    not blocked or deduplicated: AshOban's worker is unique on `period:
    :infinity, states: :incomplete` over its whole args, and the next phase's
    `action_arguments.at` differs (verified, see Framework claims). Enqueuing
    the same game and boundary twice yields one job. A phase job and a hunter
    job never deduplicate against each other (different worker modules).
15. The trigger's `backoff` yields, from `job.attempt` (1 is the first failure):
    30 seconds for 1, 60 for 2, 300 for 3, 600 for every attempt from 4 up,
    including 1_000_000. Applies to both triggers' generated workers.
16. `config/config.exs` sets the Oban lifeline `rescue_after` to `{5,
    :minutes}` (was `{2, :hours}`).
17. No cut-off: an action (vote, kill, shoot, protection) created after
    `phase_ends_at` but before the job runs still succeeds and counts in the
    transition. No action validation, and no argument of `end_day`, `end_night`
    or `resolve_hunter_deadline`, changes; they keep accepting any `now` from
    direct callers.
18. Jobs for other games are unaffected: a job for game A never reads or
    changes game B, and cancelling (rules 22-24) touches only the named game's
    jobs.
19. Authorization: the AshOban worker reads and updates as no actor with
    `AshOban.authorize?/0` true (its default), and Game's read policy would
    return nothing for a nil actor, which AshOban treats as "no longer applies"
    and cancels. So `Game`'s policies gain, first, `bypass
    AshOban.Checks.AshObanInteraction do authorize_if always() end`, and both
    new actions are added to the existing `authorize_if always()` action list.
    Non-scheduler callers are unchanged: a non-seated actor still reads no
    games, and the new actions carry no wider access than `end_day` today. No
    global `config :ash_oban, authorize?: false`.
20. Mirror of rule 11: `:end_phase_on_schedule`, when rule 9 passes, changes
    nothing and returns the 30-second snooze error while the game has
    `pending_hunter_id` set and `hunter_deadline_at` strictly before `at`
    (the hunter's deadline is due first and unprocessed).
21. The two snooze conditions cannot both hold for one game: a phase job
    snoozes only when `hunter_deadline_at < phase_ends_at` (its `at`), a hunter
    job only when `phase_ends_at <= hunter_deadline_at`. Exactly one of the two
    jobs can proceed at any moment, so neither waits on the other forever. (A
    tie goes to the phase job.)
22. Finishing a game, by any route (`Game :finish`, so also the win checks in
    `ResolveWin`), cancels that game's pending `:end_phase` and
    `:hunter_deadline` jobs in the same transaction. Only jobs in states
    `available`, `scheduled` or `retryable` are cancelled (decision 11), so
    the job currently running is not killed. `:finish` has no
    `require_atomic? false` today (`game.ex:174-184`); add it (or give the
    change an `atomic/3`), or the new hook makes `:finish` refuse to run.
23. A hunter shot, chosen or fallback, cancels that game's pending
    `:hunter_deadline` job in the same transaction: done in `HunterWindow.clear/2`,
    which `ApplyShot` already calls. It cancels no phase job. Same state rule
    as rule 22.
24. Cancelling targets jobs by their worker and by the game id inside the job's
    `args["primary_key"]["id"]`, through `Oban.cancel_all_jobs/1` with a query
    (rule 22-23's helper is `ScheduledJobs.cancel_phase_jobs/1` and
    `cancel_hunter_jobs/1`, each taking a game). Cancelling when nothing is
    pending succeeds and does nothing.
25. When a game finishes mid-phase or at dusk, no pending job remains for it:
    rule 5's night job, enqueued before the dusk win check, is cancelled by
    rule 22.
26. Row lock (checked by reading in review; no test can fail, the Ecto
    sandbox shares one connection): rules 9-12's re-read of the game uses
    `lock: :for_update` inside the action's own transaction, as
    `ResolveHunterDeadline` already does, so two jobs for one game serialise and
    the second sees the first's result. Reviewer confirms by reading that the
    read is `lock: :for_update`, happens inside the action's transaction before
    the checks, and that the trigger's own `lock_for_update?` being off does not
    matter.
27. Lobby and finished games with stale `phase_ends_at`, and a hunter job for
    a finished game, never produce an error, only a no-op or a cancelled job.

## Out of scope

- A cron entry, `scheduler_cron` string, or sweeper that re-enqueues overdue
  games (dropped by the owner).
- An `on_error` action or any new attribute (owner decision).
- A backfill or migration for games already in play (decision 8).
- Strict cut-offs or any action-validation change: werewolf_ash-qss.15.
- Push notifications for phase changes (werewolf_ash-o25.7, which this bead
  blocks) and any new GraphQL field, mutation or subscription, including
  exposing the two new actions.
- Removing the now-unused `Oban.Plugins.Cron` from config: harmless.
- Changing `end_day`, `end_night`, `start`, `resolve_hunter_deadline` or the
  window rules; this bead only adds callers, two wrapper actions and enqueues.
- An auto-start of lobby games at a set time: no bead owns it.
- A global `config :ash_oban, authorize?: false` (rule 19 uses the bypass).

## Acceptance

- `ScheduledJobs.schedule_phase_end/1` — a game yields one `:end_phase` job on
  `:game_clock`, `scheduled_at` = `phase_ends_at`, action argument `at` the
  ISO8601 of it; the same game and boundary twice leaves one job; a different
  `phase_ends_at` gives a second job.
- `ScheduledJobs.schedule_hunter_deadline/1` — one `:hunter_deadline` job,
  `scheduled_at` = `hunter_deadline_at`.
- `ScheduledJobs.cancel_phase_jobs/1` and `cancel_hunter_jobs/1` — cancel only
  that game's pending jobs of their kind (a second game's jobs stay); a job in
  state `executing` is not cancelled; cancelling with none pending returns
  successfully.
- `Game :end_phase_on_schedule` via `Ash.update` (`Games` code interface entry
  if added): with the game's current boundary it advances the game once, with
  `Phase.started_at`/`ended_at` = the recorded boundary and not the wall clock;
  a mismatched `at`, a `:lobby` game and a `:finished` game (with
  `phase_ends_at` set) change nothing and return `:ok`, creating no `Phase`; a
  second run creates no extra `Phase`; a day-boundary job does not end a later
  day; snoozes (returns the snooze error) when the hunter's deadline is
  strictly earlier than `at`.
- `Game :hunter_deadline_on_schedule`: open window at its deadline shoots one
  living player (`pick` is not accepted; assert exactly one new death and a
  fallback-flagged `:shoot` row) and clears the window; stale `at`, nil
  pointer, lobby and finished game change nothing; snoozes when
  `phase_ends_at <= at`. Also the tie case: with `phase_ends_at == at`, the
  hunter job snoozes and the phase job does not.
- Generated worker modules (`Worker.perform/1` via `perform_job/2`,
  `Worker.backoff/1`, `Worker.new/1`) — perform returns `:ok` and advances the
  game for a game the caller has no seat in (proves rule 19's bypass); a stale
  job returns `:ok` or `{:cancel, :trigger_no_longer_applies}` per rules 2, 9;
  snooze returns `{:snooze, 30}`; `backoff/1` returns 30, 60, 300 for attempts
  1, 2, 3 and 600 for 4, 5 and 1_000_000; `Worker.new(%{}).changes.max_attempts`
  is 1_000_000 for both triggers.
- Failure (rule 13): force a real failure by setting the game's `timezone`
  column to an invalid zone directly with `Repo.update_all` (bypassing
  `KnownTimezone`), so `AdvancePhase` cannot compute the next boundary; the
  job returns an error or raises, and the game and its phases are unchanged.
- `Game.Changes.AdvancePhase.change/3` — `Games.start_game`, `end_day` and
  `end_night` each leave exactly one `:end_phase` job with `scheduled_at` =
  the new `phase_ends_at`; a lobby game (created, settings updated) leaves
  none.
- `Game.HunterWindow.open/4` — leaves one `:hunter_deadline` job with
  `scheduled_at` = `hunter_deadline_at`; `clear/2` cancels it and leaves no
  new job.
- `Game :finish` (`Games.finish_game/2`) — cancels the game's pending phase
  and hunter jobs, not another game's; a hunter shot (chosen and fallback)
  cancels the pending hunter job and leaves the phase job.
- End to end (Oban `testing: :manual`, injected times, no sleep): start a game
  with a fixed `now`; assert the phase job is enqueued with the right
  `scheduled_at` and args; then `Oban.drain_queue(queue: :game_clock,
  with_scheduled: cutoff, with_recursion: true)` where `cutoff` is a fixed
  `DateTime` a few days after `now`. A bare `with_scheduled: true` with
  recursion never stops, because each phase end enqueues the next job
  (`deps/oban/lib/oban/queues/drainer.ex:37` and `:62`). Assert phases were
  replayed in order, each `Phase.started_at`/`ended_at` is the recorded
  boundary and none is the wall clock, and that the next job beyond the cutoff
  stays scheduled. Second path: lynch the hunter at dusk, assert the night's
  phase job and the hunter job exist, drain past both deadlines and see the
  fallback shot resolve. Third path: a win that ends the game at dusk leaves
  no pending job (rule 25). Ordering, one test per direction: (a) the hunter
  job is fetched first while the phase boundary is earlier: snoozes; (b) a
  phase job whose `at` is later than the hunter deadline snoozes until the
  hunter job has run. Drive both with `perform_job`, not a drain: a snoozed
  job is rescheduled to wall-clock now + 30 s (`basic.ex:278`), past any
  drain cutoff built from injected dates, so a drain never re-stages it.
- Existing suite: run `mix test`; no assertion found stale (see Touches).

## Framework claims (verified against `deps/`)

- **Trigger with no scheduler** — `scheduler_cron` is `{:or, [:string, {:literal, false}]}`
  (`deps/ash_oban/lib/ash_oban.ex:275-281`). The transformer defines only the
  worker when it is false (`lib/transformers/define_schedulers.ex:23-45`), and
  `AshOban.config` filters such triggers out of the crontab and requires no
  cron plugin for them (`ash_oban.ex:1165-1180`), but still checks the queue is
  listed (`ash_oban.ex:1271-1284`). The `Game` resource's own domain is picked up
  by default; `Games` is already in `ash_domains`.
- **`run_trigger`** — `AshOban.run_trigger/3` builds the job and calls
  `Oban.insert!`; `scheduled_at` and other unknown options go to
  `Worker.new`, `action_arguments` become `args["action_arguments"]`
  (`ash_oban.ex:944-1040`). `Oban.insert!` uses `WerewolfAsh.Repo`, so inside the
  action it commits or rolls back with it, as
  `lib/werewolf_ash/accounts/user/senders/send_magic_link_email.ex:83` already
  relies on.
- **`where` is re-applied by the worker** — its `query/0` applies `where`
  (`define_schedulers.ex:1010-1023`), the read returns nil when it no longer
  matches, and the worker returns `{:cancel, :trigger_no_longer_applies}`
  (`define_schedulers.ex:1258-1275`).
- **`lock_for_update?`** — default true (`ash_oban.ex:257-262`); it only puts
  `lock: :for_update` on the worker's own read (`define_schedulers.ex:471-490`),
  which happens before the action's transaction opens
  (`define_schedulers.ex:1245-1300`, no wrapping transaction; verified in
  review that nothing wraps it, so the lock is released as soon as the read
  finishes). That is why rule 26 has the action
  do its own locked re-read, and why the trigger sets it false.
- **Uniqueness** — the worker is `unique: [period: :infinity, states:
  :incomplete]` (`define_schedulers.ex:~372-380`); Oban compares fields worker,
  queue and whole args when no `keys` are given, and `incomplete` includes
  `executing` (`deps/oban/lib/oban/engines/basic.ex:487-540`, `job.ex:417`). The
  next phase's job differs in `action_arguments.at`, so it is not dropped while
  the current job executes. Unverified: whether `Job.new` normalises non-string
  args before that compare; the spec avoids it by passing `at` as a string.
- **`max_attempts` and `backoff` on a trigger** — both options exist
  (`ash_oban.ex:330-336, 460-480`); `backoff` emits `def backoff(job)` on the
  worker (`define_schedulers.ex:~575-590`). `job.attempt` is the attempt that
  just failed and starts at 1: fetching a job increments `attempt` from 0
  (`basic.ex:135-136`) before it runs, and the executor calls
  `worker.backoff(job)` with that job on error (`queues/executor.ex:236`).
  Oban's own default would not do with this `max_attempts`: it scales
  `attempt` by it (`deps/oban/lib/oban/worker.ex:509-517`). Unverified: whether
  the DSL accepts an anonymous `fn` for `backoff` once stored and unquoted into
  the worker (the option type is `{:fun, 1}`, emitted as
  `unquote(fun).(job)`, `define_schedulers.ex:612-623`); use an external capture (`&ScheduledJobs.backoff/1`, a public
  function on the helper module) first, and confirm via the direct
  `Worker.backoff/1` test above.
- **Snooze and cancel from an action** — `AshOban.Errors.SnoozeJob` /
  `CancelJob` errors returned or added from an action become `{:snooze, n}` /
  `{:cancel, reason}` (`ash_oban.ex:1357-1373`, `lib/errors/snooze_job.ex`);
  the worker's `rescue` maps them (`define_schedulers.ex:1342-1352`); any other
  error is reraised so Oban retries.
- **Policy side** — `AshOban.authorize?/0` defaults true (`ash_oban.ex:891-893`);
  the worker passes `authorize?: AshOban.authorize?()` and no actor, and sets
  the query and changeset context `private.ash_oban?: true`
  (`ash_oban.ex:807-832`), which `AshOban.Checks.AshObanInteraction` matches
  (`lib/checks/ash_oban_interaction.ex`). Without the bypass the seat-gated
  read policy (`game.ex` `policy action_type(:read)`) filters the game out
  and the job would cancel; the three existing `authorize_if always()` actions
  would otherwise be fine.
- **Cancel** — `Oban.cancel_all_jobs/1` takes a queryable, sets state
  `cancelled` on any job not already cancelled, completed or discarded, via
  `Repo.update_all` on the Oban repo (`deps/oban/lib/oban.ex:1558-1570`,
  `engines/basic.ex:318-329`), so inside the action it joins the open
  transaction. It also signals a kill for `executing` jobs, which is why
  rules 22-23 exclude them from the query. Unverified: that the kill signal
  is only delivered on commit; excluding `executing` makes it moot.
- **Drain** — `with_scheduled: %DateTime{}` stages only jobs due by that time;
  `with_recursion: true` loops until a pass runs nothing new
  (`drainer.ex:17-20, 28-40, 62`).
- **Lifeline** — `lifeline: [rescue_after: ...]`, default 60 minutes
  (`deps/oban/lib/oban/lifeline.ex:38, 75`); rescued jobs return to
  `available` when `attempt < max_attempts` (`basic.ex:195-210`).
- **Stager** — default 1 s interval (`stager.ex:16`), so a past `scheduled_at`
  runs within about a second; a past `scheduled_at` inserts as `scheduled`
  (`job.ex:684-690`).

## Touches

Advisory: the coder may deviate. Files the rules will probably reach:

- `lib/werewolf_ash/games/game.ex` (`AshOban` extension, `oban` section, two
  actions, policies, `:finish` cancel change)
- `lib/werewolf_ash/games/game/scheduled_jobs.ex` (new: enqueue, cancel,
  `backoff/1`)
- `lib/werewolf_ash/games/game/changes/end_phase_on_schedule.ex` and
  `lib/werewolf_ash/games/game/changes/hunter_deadline_on_schedule.ex` (new,
  names at the coder's choice)
- `lib/werewolf_ash/games/game/changes/cancel_scheduled_jobs.ex` (new, on
  `:finish`)
- `lib/werewolf_ash/games/game/changes/advance_phase.ex` (enqueue in the
  `after_action` hook; moduledoc)
- `lib/werewolf_ash/games/game/hunter_window.ex` (`open/4` enqueues, `clear/2`
  cancels; moduledoc)
- `lib/werewolf_ash/games/game/changes/resolve_hunter_deadline.ex` (moduledoc
  only)
- `lib/werewolf_ash/games.ex` (optional code interface entries)
- `config/config.exs` (`queues`, lifeline `rescue_after`)
- `CLAUDE.md` (rule text above; the owner edits it, coders are refused)
- New tests: `test/werewolf_ash/games/game/scheduled_jobs_test.exs`,
  `test/werewolf_ash/games/game/changes/*_on_schedule_test.exs`, additions to
  `advance_phase_test.exs` and `hunter_window_test.exs`.

No new attribute, so no migration; `oban_jobs` exists
(`priv/repo/migrations/20260911161745_add_oban.exs`). `mix ash.codegen --check`
should stay clean.

### Existing tests a rule will break

Greps run:

- `grep -rn "all_enqueued\|refute_enqueued\|assert_enqueued\|Oban\.\|oban_jobs" test`
  hits `test/werewolf_ash_web/graphql/auth_test.exs:328,345,353,361,374,375,380`
  and `test/werewolf_ash/accounts/user_test.exs:103`. Every one filters on
  `worker: SendMagicLinkEmailWorker` or `queue: :emails`, so new `:game_clock`
  jobs are not seen. Unaffected.
- `grep -rn "AdvancePhase\|HunterWindow\." test` hits
  `test/werewolf_ash/games/game/hunter_window_test.exs:21,34,36`: `open/4` on a
  lobby game now also inserts a job (rule 6, harmless), and `clear/2` now
  cancels it (rule 23); neither asserts on `oban_jobs`, so both pass. The
  `advance_phase_test.exs` and `open_hunter_window_*`/`resolve_*` tests build
  changesets with `Changeset.for_update` (no hook, no job) or call the
  actions, where the extra job row is harmless.
- `grep -rn "finish_game\|update :finish\|Games.finish\|HunterWindow.clear\|clear(" lib test`
  hits `lib/werewolf_ash/games.ex:16`, `games/game.ex:174`,
  `games/reactors/resolve_win.ex:52`, `games/action/changes/apply_shot.ex:58`,
  `test/werewolf_ash/games/reactors/resolve_win_test.exs:77,79,85,104`,
  `test/werewolf_ash/games/game/changes/resolve_hunter_deadline_test.exs:68`
  and `test/werewolf_ash/games/player/policy_test.exs:87,117`. `:finish` now
  also runs the cancel helper (rule 22): a cancel with nothing pending
  succeeds (rule 24), so none of these breaks.
- `grep -rln "start_game\|Games.end_day\|Games.end_night\|end_day!\|end_night!" test lib`
  hits `test/werewolf_ash/games_test.exs`, `games/policy_end_to_end_test.exs`,
  `games/action_test.exs`, `games/reactors/resolve_win_test.exs` and
  `lib/werewolf_ash/games.ex`. They now insert an `:end_phase` job row inside
  each transition; none reads `oban_jobs` for games, and `config/test.exs:4`
  `testing: :manual` means nothing runs by itself.
- `grep -rn "ash_oban\|AshObanInteraction" lib test config` finds only
  `config/config.exs:7` (`pro?: false`); the new bypass policy is unmatched by
  any existing policy test (`test/werewolf_ash/games/game/policy_test.exs`,
  `.../player/policy_test.exs` use real actors, which never carry `ash_oban?`).
- `grep -rn "lifeline\|rescue" test` finds nothing.

No existing test's expectation is stale. The coder should still run the full
suite to confirm.
