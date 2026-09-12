defmodule WerewolfAsh.Accounts.User do
  use Ash.Resource,
    otp_app: :werewolf_ash,
    domain: WerewolfAsh.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshGraphql.Resource]

  alias Ash.Query
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

  postgres do
    table "users"
    repo WerewolfAsh.Repo
  end

  actions do
    defaults [:read]

    read :current_user do
      description "The user identified by the request's bearer token, if any."
      get? true

      # Not an action `filter expr(id == ^actor(:id))`: that makes anonymous
      # requests fail with `ReadActionRequiresActor`, whereas an anonymous
      # caller asking "who am I?" should simply get nothing.
      prepare fn
        query, %{actor: nil} -> Query.do_filter(query, false)
        query, %{actor: actor} -> Query.do_filter(query, id: actor.id)
      end
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
      Requests a magic-link sign-in token for the given email and logs it
      (dev sender; real delivery is a separate piece of work). Always
      reports the same success result whether or not the email belongs to
      a registered user, so the response can never be used to enumerate
      accounts.
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
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
