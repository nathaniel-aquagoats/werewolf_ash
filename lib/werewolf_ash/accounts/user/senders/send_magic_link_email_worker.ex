defmodule WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmailWorker do
  @moduledoc """
  Delivers a magic-link sign-in email in the background, via
  `WerewolfAsh.Mailer` (Swoosh).

  Enqueued synchronously by `SendMagicLinkEmail.send/3`, inside
  `request_magic_link`'s own database transaction, so a job is only ever
  visible to this queue once that transaction commits. Runs on its own
  `:emails` queue, distinct from `:default`, so a backlog of email sends can
  never delay game jobs.

  A delivery failure — the mailer returning `{:error, reason}`, or a raised
  exception — is surfaced as a failure so Oban retries it, rather than being
  swallowed into `:ok` the way the old inline sender's `deliver/2` did: Oban
  only retries a job whose `perform/1` reports failure. `max_attempts: 8`
  with Oban's default exponential backoff gives roughly 6 minutes and 8
  attempts before the job is discarded for good and the player has to
  request a new link.

  Uniqueness (one unfinished job per address at a time) is computed on the
  job's own `dedupe_key` arg — an already-lowercased copy of the address,
  built by `SendMagicLinkEmail` — never on `email` as typed or looked up,
  which can differ in casing between the two call sites in
  `AshAuthentication.Strategy.MagicLink.Request.run/3`. `period: :infinity`
  means age never exempts a still-unfinished job from the match (Oban's own
  60-second default would let a same-address request through far sooner than
  this worker's own retry window allows); `states: :incomplete` covers
  available, scheduled, executing, retryable and suspended jobs, so a
  *finished* job (delivered, discarded, or a no-op under an expired token)
  never blocks a fresh request.

  Performing a job whose token has already expired by the time it runs sends
  no email and is not a failure: only the token's own `exp` claim is
  checked, via `AshAuthentication.Jwt.peek/1`, deliberately not
  `Jwt.verify/4` (which also checks the signature and whether the token was
  already consumed or revoked) — an already-used-but-not-yet-expired token is
  out of scope here and still gets a delivery attempt.
  """

  use Oban.Worker,
    queue: :emails,
    max_attempts: 8,
    unique: [keys: [:dedupe_key], period: :infinity, states: :incomplete]

  alias AshAuthentication.Jwt
  alias Swoosh.Email
  alias WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmail
  alias WerewolfAsh.Mailer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email" => email, "token" => token}}) do
    if expired?(token) do
      :ok
    else
      deliver(email, token)
    end
  end

  defp expired?(token) do
    case Jwt.peek(token) do
      {:ok, %{"exp" => exp}} -> exp < System.system_time(:second)
      _ -> false
    end
  end

  defp deliver(email, token) do
    link = SendMagicLinkEmail.magic_link_url(token)
    from = Application.fetch_env!(:werewolf_ash, :magic_link_from_address)

    message =
      Email.new()
      |> Email.to(email)
      |> Email.from(from)
      |> Email.subject("Your Werewolf sign-in link")
      |> Email.text_body("Click this link to sign in:\n\n#{link}")

    case Mailer.deliver(message) do
      {:ok, _receipt} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
