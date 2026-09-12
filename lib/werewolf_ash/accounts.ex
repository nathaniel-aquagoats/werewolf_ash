defmodule WerewolfAsh.Accounts do
  use Ash.Domain,
    otp_app: :werewolf_ash,
    extensions: [AshGraphql.Domain]

  graphql do
    queries do
      read_one WerewolfAsh.Accounts.User, :current_user, :current_user
    end

    mutations do
      # A generic action, not a read: it mutates server state (a stored
      # token) and never reveals whether the given email matched a user, so
      # its result is a plain success boolean rather than the user/token.
      action WerewolfAsh.Accounts.User, :request_magic_link, :request_magic_link do
        args [:email]
      end

      # A create action (magic link registration is enabled, so signing in
      # upserts the user by email): standard create-mutation `result` /
      # `metadata` / `errors` shape, with the JWT in `metadata { token }`.
      create WerewolfAsh.Accounts.User, :sign_in_with_magic_link, :sign_in_with_magic_link do
        args [:token]
        hide_inputs [:remember_me]
      end

      # `read_action :current_user` (rather than the default primary read,
      # which no policy grants) is what makes this reachable at all: it
      # resolves the record to update from the request's actor, so
      # `identity false` is correct too — there is no `id` input to look up.
      update WerewolfAsh.Accounts.User, :set_name, :set_name do
        identity false
        read_action :current_user
        args [:name]
      end
    end
  end

  resources do
    resource WerewolfAsh.Accounts.Token

    resource WerewolfAsh.Accounts.User do
      define :set_name, args: [:name]
    end
  end
end
