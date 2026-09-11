defmodule WerewolfAsh.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        WerewolfAsh.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:werewolf_ash, :token_signing_secret)
  end
end
