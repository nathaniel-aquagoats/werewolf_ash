defmodule WerewolfAsh.Accounts do
  use Ash.Domain,
    otp_app: :werewolf_ash,
    extensions: [AshGraphql.Domain]

  graphql do
    queries do
      read_one WerewolfAsh.Accounts.User, :current_user, :current_user

      # Sign in is a read action whose `token` metadata is exposed on the
      # `UserWithToken` type. It mutates server state (a stored token), so it
      # is placed under `mutation`.
      read_one WerewolfAsh.Accounts.User, :sign_in_with_password, :sign_in_with_password do
        type_name :user_with_token
        as_mutation? true
        allow_nil? false
      end
    end

    mutations do
      create WerewolfAsh.Accounts.User, :register_with_password, :register_with_password
    end
  end

  resources do
    resource WerewolfAsh.Accounts.Token
    resource WerewolfAsh.Accounts.User
  end
end
