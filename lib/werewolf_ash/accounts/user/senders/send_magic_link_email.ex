defmodule WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmail do
  @moduledoc """
  Requests a magic-link sign-in token be emailed, by enqueueing a background
  job that delivers it via `WerewolfAsh.Mailer`.

  `send/3` itself never touches the mailer: it hands delivery off to
  `WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmailWorker`, an Oban job on
  its own `:emails` queue, enqueued synchronously (never from a spawned
  process or `Task`) as part of `request_magic_link`'s own transaction — so
  the job only becomes visible once that transaction commits. This is
  intentional per CLAUDE.md's Oban conventions: sending an email is
  background work, not something the request needs to wait on.

  Only one such job is ever unfinished per address at a time (case-
  insensitively): a further request while one is still queued, scheduled,
  executing or retrying enqueues no second job, so mashing "resend" doesn't
  pile up duplicate emails. See the worker's own moduledoc for the delivery
  and retry behaviour.

  `:dev` and `:test` also still print the token and deep link to the
  console, purely for local convenience, synchronously and regardless of
  what happens to the enqueued job.

  Tests capture the token without touching the console: register a pid with
  `Application.put_env(:werewolf_ash, :magic_link_test_pid, self())` and this
  sender also forwards `{:magic_link_token, email, token}` to it. That
  forwarding (and even consulting `magic_link_test_pid` at all) is gated by a
  *compile-time* flag — `Application.compile_env(:werewolf_ash,
  :magic_link_test_hook?, false)`, backed by `config_env() == :test` in
  config — never a runtime check of which environment is running: that would
  raise `UndefinedFunctionError` under a `mix release` build (the build tool's
  own application isn't part of one), which is exactly where `send/3` also
  has to run in `:prod`.
  """

  use AshAuthentication.Sender

  alias WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmailWorker

  @test_hook? Application.compile_env(:werewolf_ash, :magic_link_test_hook?, false)

  @impl true
  def send(user_or_email, token, _opts) do
    # A user if the token relates to an existing account; a plain email if
    # there is no matching user (e.g. during sign-up).
    email =
      case user_or_email do
        %{email: email} -> to_string(email)
        email -> to_string(email)
      end

    link = magic_link_url(token)

    IO.puts("""
    Hello, #{email}! Click this link to sign in:

    #{link}
    """)

    enqueue_delivery(email, token)
    maybe_forward_to_test_pid(email, token)

    :ok
  end

  @doc """
  Builds the deep link a magic-link email points at: the configured base
  URL, looked up at call time, with `?token=<token>` appended.
  """
  def magic_link_url(token) do
    base_url = Application.fetch_env!(:werewolf_ash, :magic_link_deep_link_base_url)
    "#{base_url}?token=#{token}"
  end

  # The job's args are the minimum needed to send later, plus a lowercased
  # copy of the address to dedupe on (rule 11): `email`/`token` as typed and
  # looked up may differ in casing between the two call sites in
  # `AshAuthentication.Strategy.MagicLink.Request.run/3`, but the dedupe key
  # is always normalized so `Foo@Example.com` and `foo@example.com` collide.
  defp enqueue_delivery(email, token) do
    %{"email" => email, "token" => token, "dedupe_key" => String.downcase(email)}
    |> SendMagicLinkEmailWorker.new()
    |> Oban.insert()
  end

  if @test_hook? do
    defp maybe_forward_to_test_pid(email, token) do
      case Application.get_env(:werewolf_ash, :magic_link_test_pid) do
        pid when is_pid(pid) -> Kernel.send(pid, {:magic_link_token, email, token})
        _ -> :ok
      end
    end
  else
    defp maybe_forward_to_test_pid(_email, _token), do: :ok
  end
end
