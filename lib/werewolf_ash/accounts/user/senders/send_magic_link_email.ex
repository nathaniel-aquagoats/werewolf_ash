defmodule WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmail do
  @moduledoc """
  Sends a magic-link sign-in token.

  Only logs the link for now; real email delivery is a separate piece of
  work (bead werewolf_ash-27w.8).

  Tests capture the token without touching the log: register a pid with
  `Application.put_env(:werewolf_ash, :magic_link_test_pid, self())` and
  this sender also forwards `{:magic_link_token, email, token}` to it.
  """

  use AshAuthentication.Sender

  @impl true
  def send(user_or_email, token, _opts) do
    # A user if the token relates to an existing account; a plain email if
    # there is no matching user (e.g. during sign-up).
    email =
      case user_or_email do
        %{email: email} -> to_string(email)
        email -> to_string(email)
      end

    IO.puts("""
    Hello, #{email}! Click this link to sign in:

    /auth/user/magic_link/?token=#{token}
    """)

    case Application.get_env(:werewolf_ash, :magic_link_test_pid) do
      pid when is_pid(pid) -> Kernel.send(pid, {:magic_link_token, email, token})
      _ -> :ok
    end
  end
end
