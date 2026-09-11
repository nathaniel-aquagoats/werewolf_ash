defmodule WerewolfAsh.Accounts.User.Senders.SendNewUserConfirmationEmail do
  @moduledoc """
  Sends an email for a new user to confirm their email address.
  """

  use AshAuthentication.Sender

  @impl true
  def send(_user, token, opts) do
    # `opts[:confirmation_type]` is `:identity_link` when an OAuth2/OIDC
    # sign-in whose email matches this already-registered account is asking
    # to be linked (the strategy's `on_untrusted_email_match :confirm`).
    # Confirming grants that provider login access to this account.
    prompt =
      case opts[:confirmation_type] do
        :identity_link ->
          "Someone signed in with #{opts[:provider]} using your email address. " <>
            "If it was you, confirm to link it to your account:"

        _ ->
          "Click this link to confirm your email:"
      end

    IO.puts("""
    #{prompt}

    /confirm_new_user/#{token}
    """)
  end
end
