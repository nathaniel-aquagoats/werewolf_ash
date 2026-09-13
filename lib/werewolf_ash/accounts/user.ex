defmodule WerewolfAsh.Accounts.User do
  use Ash.Resource,
    otp_app: :werewolf_ash,
    domain: WerewolfAsh.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshGraphql.Resource]

  alias AshAuthentication.Strategy.MagicLink.Request

  authentication do
    add_ons do
      log_out_everywhere do
      end
    end

    tokens do
      enabled? true
      token_resource WerewolfAsh.Accounts.Token
      signing_secret WerewolfAsh.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      remember_me :remember_me

      # `registration_enabled?`: the only way to get an account is to sign in
      # with a magic link, so the sign-in action itself must be able to
      # create the user (an upsert by email) on first use.
      #
      # `require_interaction?`: this only changes behaviour for the
      # AshAuthenticationPhoenix router/plug (GET vs POST on a web page),
      # which this API-only app doesn't use — the token is always consumed
      # by an explicit `signInWithMagicLink` GraphQL mutation, never a
      # followed link. Set to `true` anyway: it matches the "explicit POST"
      # shape our GraphQL mutation already has, and it silences a compile
      # warning that otherwise fires on every build.
      magic_link do
        identity_field :email
        registration_enabled? true
        require_interaction? true

        sender WerewolfAsh.Accounts.User.Senders.SendMagicLinkEmail
      end
    end
  end

  graphql do
    type :user
  end

  field_policies do
    # rule 17 - :email is visible on the actor's own row, and on the two
    # production paths that read it with no actor at all: an already-
    # registered email's magic-link request (the AshAuthenticationInteraction
    # context), and sign_in_with_magic_link's own create (matched by action
    # name, since AshGraphql's create mutation never sets that context).
    field_policy :email do
      authorize_if AshAuthentication.Checks.AshAuthenticationInteraction

      # AshGraphql's create mutation calls Ash.create/2 directly, never
      # AshAuthentication.Strategy.MagicLink.Actions.sign_in/3, so the
      # ash_authentication? context above is never set on this path.
      # Every create's result is field-policy-checked a second time, though,
      # via the automatic post-create reload (`Ash.Actions.Create.run/4`
      # reloading through the resource's primary read action so any
      # requested calculations/aggregates resolve) - that reload's own
      # query carries `context.private.just_created_by_action`, set to the
      # action that just ran, regardless of what the reload's own read
      # action is named. `action(:sign_in_with_magic_link)` cannot be used
      # here instead: it matches the *read* action driving that reload
      # (never :sign_in_with_magic_link), not the create that produced the
      # record.
      authorize_if context_equals([:private, :just_created_by_action], :sign_in_with_magic_link)

      authorize_if expr(id == ^actor(:id))
    end

    # :id and :name need no "shares a game" condition: this only decides
    # whether a *visible* row's field is readable, and a signed-in user with
    # no games yet must still see their own name via currentUser.
    field_policy :* do
      authorize_if always()
    end
  end

  postgres do
    table "users"
    repo WerewolfAsh.Repo
  end

  actions do
    defaults [:read]

    read :current_user do
      description "The user identified by the request's bearer token, if any."
      get? true

      # No custom prepare: this action's own policy below
      # (`authorize_if expr(id == ^actor(:id))`) already filters an
      # anonymous actor and a mismatched actor to nothing, without raising
      # `ReadActionRequiresActor` - that error only comes from an *action*
      # level `filter expr(...)` referencing the actor, not from a read
      # policy.
    end

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end

    create :sign_in_with_magic_link do
      description "Sign in or register a user with magic link."

      argument :token, :string do
        description "The token from the magic link that was sent to the user"
        allow_nil? false
      end

      argument :remember_me, :boolean do
        description "Whether to generate a remember me token"
        allow_nil? true
      end

      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email]

      # Uses the information from the token to create or sign in the user
      change AshAuthentication.Strategy.MagicLink.SignInChange

      change {AshAuthentication.Strategy.RememberMe.MaybeGenerateTokenChange,
              strategy_name: :remember_me}

      metadata :token, :string do
        allow_nil? false
      end
    end

    action :request_magic_link, :boolean do
      description """
      Requests a magic-link sign-in token for the given email and emails it
      as a deep link to the mobile app. Always reports the same success
      result whether or not the email belongs to a registered user, so the
      response can never be used to enumerate accounts.
      """

      argument :email, :ci_string do
        allow_nil? false
      end

      # Delegates to the strategy's own request implementation (which looks
      # up the user, if any, and invokes the sender), then coerces its
      # `:ok` / `{:error, reason}` result to the boolean this action
      # advertises. The only error path here is a genuine lookup failure
      # (e.g. the database is unreachable) - "no such user" already returns
      # `:ok` from the strategy so as not to leak which emails are registered.
      run fn input, context ->
        case Request.run(input, [], context) do
          :ok -> {:ok, true}
          {:error, error} -> {:error, error}
        end
      end
    end

    update :set_name do
      description "Sets the acting user's own display name."
      accept [:name]
      require_attributes [:name]
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action([:request_magic_link, :sign_in_with_magic_link]) do
      description "Anyone may request a magic link or sign in with one; the actions verify the token themselves."
      authorize_if always()
    end

    policy action(:current_user) do
      description "A user may only read themselves."
      authorize_if expr(id == ^actor(:id))
    end

    policy action(:set_name) do
      description "A user may only set their own display name."
      authorize_if expr(id == ^actor(:id))
    end

    # rule 17 - a signed-in actor may also read a fellow player's row: any
    # `User` that shares a seat in at least one game with the actor. This is
    # what lets `Player.user`/`Message.author.user` resolve for a fellow
    # player, not just for yourself.
    policy action(:read) do
      description "A user may read a fellow user who shares a seat with them in some game."
      authorize_if expr(exists(players, exists(game.players, user_id == ^actor(:id))))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      description "The user's own chosen display name; absent until they set it."
      allow_nil? true
      public? true
      constraints min_length: 1, max_length: 40, trim?: true
    end
  end

  relationships do
    has_many :players, WerewolfAsh.Games.Player do
      description "The seats this user holds across games; expresses which games they're in."
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
