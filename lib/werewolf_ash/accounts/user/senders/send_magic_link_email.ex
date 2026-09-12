defmodule WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmail do
  @moduledoc """
  Sends a magic-link sign-in token by email, via `WerewolfAsh.Mailer`.

  A `Swoosh.Email` is built and handed to `WerewolfAsh.Mailer.deliver/1` in
  every environment; delivery is never a bare `IO.puts`/`Logger` call
  standing in for it. Which adapter actually backs the mailer differs per
  environment (see `config/*.exs`): a real, network-based adapter (Resend) in
  `:prod`, a non-network one (`Swoosh.Adapters.Test`) in `:dev`/`:test` — so
  neither `mix phx.server` nor `mix test` ever makes a real network call or
  needs a provider credential. `:dev` and `:test` also still print the token
  and deep link to the console, purely for local convenience.

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

  require Logger

  alias Swoosh.Email
  alias WerewolfAsh.Mailer

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

    deliver(email, link)
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

  defp deliver(email, link) do
    from = Application.fetch_env!(:werewolf_ash, :magic_link_from_address)

    message =
      Email.new()
      |> Email.to(email)
      |> Email.from(from)
      |> Email.subject("Your Werewolf sign-in link")
      |> Email.text_body("Click this link to sign in:\n\n#{link}")

    case Mailer.deliver(message) do
      {:ok, _receipt} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to send magic-link email to #{email}: #{inspect(reason)}")
        :ok
    end
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
