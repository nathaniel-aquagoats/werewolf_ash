defmodule WerewolfAsh.Accounts do
  use Ash.Domain,
    otp_app: :werewolf_ash

  resources do
    resource WerewolfAsh.Accounts.Token
    resource WerewolfAsh.Accounts.User
  end
end
