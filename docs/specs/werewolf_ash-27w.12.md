# werewolf_ash-27w.12: Send magic-link sign-in emails from an Oban job

Implemented in PR #23.

Depends on: none

## For the owner

**What changes.** Requesting a sign-in link no longer waits on the email
provider: the request enqueues a background job and returns immediately, and
the job sends the email a moment later. If the provider hiccups, the job
retries a few times on its own before giving up; if you tap the link button
again while an email is still on its way, nothing extra gets sent.

**Decisions.**
1. Can the sign-in link's token sit in the background-job table until it's
   cleaned up? — **Decided:** yes; it expires in 10 minutes and works once.

**Rule changes.** None — CLAUDE.md's existing Oban rule already names "an
email" as the example of background work this bead implements.

## Assumptions

- **Retry count.** 8 total attempts, using Oban's own default exponential
  backoff, lands the job's final, giving-up attempt roughly 6 minutes after
  the first — the closest whole-attempt fit to the owner's "roughly 5
  minutes" (no built-in backoff lands on exactly 5). Implementation choice,
  not a card decision; see Rule 5.
- **Raw token in the job table (the risk, stated plainly).** The job's args
  carry the sign-in link's actual token in plain form in `oban_jobs`,
  persisted there until the pruner clears it (`config/config.exs:14`,
  currently up to 1 day after the job finishes). Anyone with database access
  to `oban_jobs` — or, if ever mounted, an Oban Web dashboard — can read a
  queued or recently-finished job's token and use it to sign in as that
  address until it expires or is used. Accepted per Decisions: it expires in
  10 minutes and is single-use, and reading it requires the same database
  access that already exposes everything else in this app.
- **Case-insensitive dedup.** "One queued email per address" (Rule 6) is read
  as case-insensitive, matching the existing `:ci_string` identity field on
  `User.email`, so `Foo@Example.com` and `foo@example.com` collide as the
  same address. Implementation choice, not a card decision. Oban's own
  uniqueness has no case-insensitive option — it's an exact Postgres JSONB
  containment check (`deps/oban/lib/oban/engines/basic.ex:507-524`) — so this
  is achieved with a separate, already-lowercased dedupe key (Rule 6), not by
  folding case at compare time.

## Goal

Requesting a magic-link sign-in no longer sends the email inline: it hands the
send off to a background job and returns without waiting on the mail
provider. The job does the actual sending a moment later, retries itself a
handful of times if the provider is unreachable, and gives up rather than
retrying forever. Only one such job is ever in flight per address at a time,
so mashing the "resend" button doesn't pile up duplicate emails; once that job
is done (sent, given up, or the link inside it went stale before it ran), a
fresh request is free to queue another. None of this changes what a player
sees: the same link, sent to the same address, still signs them in exactly as
it does today.

## Rules

1. `WerewolfAsh.Accounts.User`'s `request_magic_link` action runs inside a
   database transaction (`transaction? true`). Today it does not: a generic
   Ash action's `transaction?` defaults to `false`
   (`deps/ash/lib/ash/resource/actions/action/action.ex:20`), so nothing in
   the action currently participates in a shared transaction. A direct test
   asserts `Ash.Resource.Info.action(WerewolfAsh.Accounts.User,
   :request_magic_link).transaction? == true`
   (`deps/ash/lib/ash/resource/info.ex:716`) — this rule has no other
   independently observable effect in a test, since `Request.run/3` ignores
   whatever `send/3` returns either way, and the Ecto sandbox hides the
   difference in commit visibility that this rule is actually for.
2. A call to `request_magic_link` enqueues exactly one Oban job to send that
   request's email, and the enqueue happens synchronously as part of the
   action (inside the transaction from Rule 1) — never from a spawned
   process, `Task`, or other async work.
   - Why Rule 1 makes this true: the action's `run` function calls
     `AshAuthentication.Strategy.MagicLink.Request.run/3`
     (`deps/ash_authentication/lib/ash_authentication/strategies/magic_link/request.ex`),
     which calls the configured sender's `send/3` synchronously, in the same
     process, before returning. With `transaction? true`, Ash wraps that
     whole call chain in `Ash.DataLayer.transaction/4`
     (`deps/ash/lib/ash/actions/action.ex:180-223`), which for
     `AshPostgres.DataLayer` resolves to `repo.transaction(fun)` on the
     resource's own repo (`deps/ash_postgres/lib/data_layer.ex:4527-4545`) —
     `WerewolfAsh.Repo` for `User`, the same repo Oban is configured with
     (`config/config.exs:9-16`). Ecto's `transaction/2` and `checkout/2`
     nest on the same repo and process
     (`deps/ecto/lib/ecto/repo.ex:794-796`), and Oban's basic engine enqueues
     with a plain `Repo.insert` (`deps/oban/lib/oban/engines/basic.ex:86`,
     `:461`) — so a job inserted from inside the sender's `send/3` lands in
     the same transaction as the rest of the request, and only becomes
     visible once that transaction commits.
3. The email job runs on its own Oban queue, distinct from `default`, so a
   backlog of email sends can never delay game jobs.
4. Performing the job delivers the email for that request through the
   existing `WerewolfAsh.Mailer` (Swoosh) path — same recipient address,
   subject, and deep-link body that today's `SendMagicLinkEmail.send/3`
   builds.
5. A delivery failure inside the job (the mailer returning an error tuple, or
   the job raising) is retried automatically by Oban, up to a total of 8
   attempts; once the 8th attempt fails, the job is discarded and
   is not retried again — the player has to request a new link. This
   replaces today's behaviour in `SendMagicLinkEmail`'s private `deliver/2`,
   which catches the mailer's `{:error, reason}`, logs it, and still returns
   `:ok`: that swallow-and-log logic must not survive inside the job, because
   Oban only retries a job whose `perform/1` reports failure (an error tuple
   or a raise) — a caught-and-logged failure looks like success and will
   never be retried. The worker's execution timeout is left at Oban's
   default, `:infinity` (`deps/oban/lib/oban/worker.ex:522-524`); this bead
   does not add a `timeout/1` callback (see Out of scope).
6. Uniqueness is computed on a dedicated, already-lowercased dedupe key
   carried in the job's args (Rule 11) — never on the address as typed or as
   looked up. Those can differ in casing at the two places `send/3` is
   called from: `to_string(identity)` (the caller's own typed casing) versus
   the found `user`'s stored `email` (the casing it was first registered
   with) — `deps/ash_authentication/lib/ash_authentication/strategies/magic_link/request.ex:48`
   and `:66`. Oban's own uniqueness match is an exact Postgres JSONB
   containment check with no case-folding
   (`deps/oban/lib/oban/engines/basic.ex:507-524`), so case-insensitivity has
   to be baked into the key's value, not the comparison. The uniqueness
   options are `period: :infinity` (not Oban's 60-second default,
   `deps/oban/lib/oban/job.ex:231`, which is far shorter than Rule 5's
   ~6-minute retry window and would let a same-address request through as
   soon as the first minute passed) and `states: :incomplete` — available,
   scheduled, executing, retryable, or suspended
   (`deps/oban/lib/oban/job.ex:432`). While a previously-enqueued job whose
   dedupe key matches is in one of those states, a further
   `request_magic_link` call for that address enqueues no second job — this
   holds regardless of how old that job is, since the period is infinite.
7. Once the job for an address has finished — delivered, discarded after
   exhausting Rule 5's retries, or completed as a no-op under Rule 8 — a
   further request for that address enqueues a fresh job; it is not blocked
   by the earlier, now-finished one. A test proving this must actually
   finish the first job's row, e.g. with `Oban.drain_queue(queue: :emails)`
   — not `Oban.Testing.perform_job/2,3`, which calls the worker's `perform/1`
   directly without acknowledging or updating the job's stored state
   (`ack: false`, `deps/oban/lib/oban/testing.ex:253-260`), so the first
   job would still read as `available` and Rule 6 would (correctly) keep
   blocking a second enqueue.
8. Performing a job whose token has already expired by the time it runs sends
   no email, and this does not count as a delivery failure: it must not be
   retried or discarded on that account the way Rule 5's failures are. The
   check reads only the token's own `exp` claim via
   `AshAuthentication.Jwt.peek/1` (`deps/ash_authentication/lib/ash_authentication/jwt.ex`)
   against the current time — it deliberately does not call `Jwt.verify/4`,
   which also checks the token's signature and, via the `jti` claim,
   whether it has already been revoked or consumed
   (`deps/ash_authentication/lib/ash_authentication/jwt/config.ex:119-139`).
   A token that has been used already but has not yet expired is out of
   scope for this rule: the job still attempts delivery. For a deterministic
   test, build an already-expired token directly with
   `AshAuthentication.Jwt.token_for_resource/4`, passing `"exp"` (a past
   Unix timestamp) in the extra-claims map — Joken skips generating a claim
   that's already present in the map it's given
   (`deps/joken/lib/joken/claim.ex:18-27`), so the forced `"exp"` survives
   into the signed token instead of being overwritten with a fresh one.
9. The console log and the `magic_link_test_pid` forwarding hook in
   `SendMagicLinkEmail.send/3` (used today by tests to capture the raw token)
   keep firing synchronously when `request_magic_link` is called, regardless
   of whether the email job is later performed, discarded, or deduplicated by
   Rule 6. Existing tests rely on this to get a working token without ever
   performing a job.
10. `request_magic_link`'s response is unaffected by any of the above: it
    keeps reporting the same success result whether this call's own job was
    newly enqueued or deduplicated by Rule 6 (already true today, since
    Oban's insert reports a unique conflict as success, not an error —
    `deps/oban/lib/oban/engines/basic.ex:447-463` — this rule pins that it
    stays true once sending moves into the job).
11. The job's stored arguments are the minimum needed to send later, plus
    Rule 6's dedupe key: the recipient address, that request's raw
    magic-link token, and a lowercased copy of the address to dedupe on —
    and nothing else (no full user record, no unrelated fields). The dedupe
    key holds no secret of its own: it's a case-normalized copy of the
    address that's already sitting in the same args map.

## Out of scope

- Any change to the `requestMagicLink` GraphQL mutation's shape, arguments,
  or return type, or to its registration in `lib/werewolf_ash/accounts.ex:15`
  — confirmed unchanged: `mobile/schema.graphql:147` stays
  `requestMagicLink(email: String!): Boolean!`. No `mix graphql.codegen` run
  is needed for this bead.
- Modelling this as an `AshOban` resource trigger or scheduled action (see
  `.claude/skills/ash-framework/references/ash_oban/`). Those run an Ash
  action against a record found by a periodic scan, keyed off persisted
  resource state — a poor fit here, since it would mean persisting the raw
  token on a queryable resource, which is worse than the raw-token-in-
  `oban_jobs` trade-off already accepted (Decisions; see Assumptions), not
  better. A plain `Oban.Worker` is the right shape.
- Tightening the `email.to == [{"", ...}]}` / `email.from == {"", ...}}`
  tuple-shape assertions in `test/werewolf_ash_web/graphql/auth_test.exs`
  (lines 273 and 304) — that's werewolf_ash-27w.10's review nit. Adapt these
  tests to perform the job before asserting (see Touches), but leave the
  assertion's shape exactly as loose as it is today; do not fix the
  brittleness while in there.
- werewolf_ash-27w.11's docs/skills/production follow-ups (CLAUDE.md wording,
  `mix usage_rules.sync`, verifying a Resend sending domain) — unrelated,
  separately tracked, do not touch.
- Changing `token_lifetime`, `single_use_token?`, or any other magic-link DSL
  option on `User` besides adding `transaction? true` to `request_magic_link`.
- A custom `backoff/1` callback or fixed-interval retry schedule. Oban's
  default exponential backoff with `max_attempts: 8` (Rule 5; see
  Assumptions) is enough; do not implement a custom one.
- A custom `timeout/1` callback on the worker. Oban's default, `:infinity`
  (`deps/oban/lib/oban/worker.ex:522-524`), is left as is (Rule 5).
- Oban Web, dashboards, or telemetry/logging integration for jobs — not
  requested and not mounted anywhere in this API-only app.

## Acceptance

- `WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmail.send/3` — for both an
  existing user and an unregistered email: enqueues exactly one job on the
  emails queue carrying the address, token, and dedupe key (Rules 2, 3, 6,
  11); still logs to the console and forwards to `magic_link_test_pid`
  synchronously regardless of enqueue outcome (Rule 9); a second call for the
  same address while the first job is unfinished enqueues no second job
  (Rule 6), including when the first job's `inserted_at` is more than 60
  seconds in the past — proving `period: :infinity`, not Oban's 60-second
  default; a call for `Foo@Example.com` followed by one for
  `foo@example.com` enqueues exactly one job between them (Rule 6's dedupe
  key); once that job has actually finished (see Rule 7's testing note), a
  further call for the same address enqueues a new one (Rule 7).
- `WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmail.magic_link_url/1` —
  unchanged contract; its existing direct tests keep passing untouched.
- The email-sending job's `perform/1` (suggested module
  `WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmailWorker` — coder may
  name or place it differently): delivers via `WerewolfAsh.Mailer` for a
  non-expired token (Rule 4); on a mailer failure, returns/raises so Oban
  counts and retries the attempt rather than swallowing it (Rule 5); for an
  already-expired token, sends nothing without being classed as a failure
  (Rule 8); is declared with its own queue (Rule 3) and `max_attempts: 8`
  (Rule 5; see Assumptions).
- `WerewolfAsh.Accounts.User`'s `:request_magic_link` action — a direct test
  (via `Ash.ActionInput.for_action/3` + `Ash.run_action/1`, independent of
  GraphQL) that it runs transactionally and enqueues through `Oban.Testing`
  assertions (Rules 1, 2).
- End to end: the `requestMagicLink` GraphQL mutation, called twice in quick
  succession for the same address, results in exactly one job enqueued
  (`Oban.Testing.assert_enqueued`/`all_enqueued`, per `config/test.exs:4`'s
  `testing: :manual`); performing that job with `Oban.Testing.perform_job/2,3`
  delivers a Swoosh-test-adapter email whose link, passed to
  `signInWithMagicLink`, signs the player in exactly as it does today.

## Touches

Advisory only; the coder may deviate.

- `lib/werewolf_ash/accounts/user.ex` — add `transaction? true` to
  `request_magic_link` (Rule 1).
- `lib/werewolf_ash/accounts/user/senders/send_magic_link_email.ex` —
  `send/3` enqueues the job instead of calling `Mailer.deliver` itself;
  update its moduledoc, which currently claims delivery happens directly
  from `send/3` "in every environment" (no longer true once delivery moves
  into the job).
- A new worker module for the job's `perform/1` (suggested location
  `lib/werewolf_ash/accounts/user/senders/send_magic_link_email_worker.ex`),
  and its own direct unit tests (suggested
  `test/werewolf_ash/accounts/user/senders/send_magic_link_email_worker_test.exs`).
- `config/config.exs:9-16` — add a distinct `emails` queue entry to the
  `config :werewolf_ash, Oban` `queues:` list (Rule 3).
- `Oban.Testing` isn't set up anywhere under `test/` today (no hit for
  `Oban.Testing` or `assert_enqueued` in the tree). Add
  `use Oban.Testing, repo: WerewolfAsh.Repo` somewhere it's reachable by both
  `auth_test.exs` and the new worker test file — a shared test-case module
  under `test/support/`, or directly in each.
- `test/werewolf_ash_web/graphql/auth_test.exs` — existing tests whose
  expectations are now stale, found via:
  `grep -n "SendMagicLinkEmail.send(\|assert_email_sent\|magic_link_test_pid\|request_token(\|assert_received {:magic_link_token" test/werewolf_ash_web/graphql/auth_test.exs`
  - `:270-277` ("delivers the email to the resolved recipient..."): stale —
    asserts `assert_email_sent` right after calling `send/3`, which no
    longer delivers anything itself. Corrected: after `send/3`, perform the
    enqueued job (e.g. `Oban.Testing.perform_job/2,3`), then assert
    `assert_email_sent` as before.
  - `:279-292` ("the deep-link base URL is read at call time..."): stale for
    the same reason. Corrected: perform the job before the `assert_email_sent`
    check; the config override already in effect for the test process still
    applies whenever the job is performed within the same test.
  - `:294-305` ("the from address is read at call time..."): same stale
    reason and same correction as the two above.
  - `:307-314` ("still logs the token and deep link to the console..."):
    **not stale** — this only asserts on `capture_io` output from `send/3`
    itself, and Rule 9 keeps that console log in `send/3`, so this test needs
    no change.
  - `:316-332` ("a failed delivery still returns :ok and logs an error"):
    stale in substance, not just mechanically — Rule 5 requires the job to
    surface a mailer failure as a retryable failure, not swallow it into
    `:ok`. Corrected: this test's subject moves from `SendMagicLinkEmail.send/3`
    (which no longer touches the mailer at all) to the job's `perform/1`;
    the corrected assertion is that `perform/1` returns an error (or raises)
    when the mailer fails, not that it returns `:ok`. Move this test (and
    the `FailingMailerAdapter` module it needs, currently defined at
    `:1-11`) to the new worker test file. That leaves `import
    ExUnit.CaptureLog` (`:23`) and `alias
    WerewolfAshWeb.Graphql.AuthTest.FailingMailerAdapter` (`:32`) with no
    other caller in `auth_test.exs` (`grep -n "capture_log\|FailingMailerAdapter"
    test/werewolf_ash_web/graphql/auth_test.exs` shows both used only by this
    one test) — remove them from `auth_test.exs` or `mix lint` fails on the
    unused import/alias.
  - `:84-89`, `:94`, `:106`, `:128`, `:157`, `:186`, `:357` (the
    `request_token/2` helper and its callers) and `:255-267`
    (`SendMagicLinkEmail.send/3`'s two `magic_link_test_pid`-forwarding
    tests): **not stale** — Rule 9 keeps this forwarding synchronous and
    independent of the job, so every test that signs in via `request_token/2`
    keeps working without performing any job.
  - `:154-171` ("requestMagicLink succeeds identically..."): **not stale** —
    it calls `requestMagicLink` a third time for `registered_email`, which by
    then already has an unfinished job from its first call (jobs never
    auto-run under `testing: :manual`); Rule 6 means that call is deduplicated,
    and Rule 10 (and `deps/oban/lib/oban/engines/basic.ex:447-463`) means a
    dedup is reported as success, not an error, so both compared responses
    stay `%{"data" => %{"requestMagicLink" => true}}` either way.
  - `:335-352` (`SendMagicLinkEmail.magic_link_url/1` tests): **not stale** —
    calls `magic_link_url/1` directly; unaffected by where it's called from.
