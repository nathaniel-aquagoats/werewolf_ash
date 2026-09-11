defmodule WerewolfAshWeb.GraphqlSocket do
  use Phoenix.Socket

  use Absinthe.Phoenix.Socket,
    schema: WerewolfAshWeb.GraphqlSchema

  alias WerewolfAsh.Accounts.BearerToken

  @doc """
  Connects the subscriptions socket, deriving the Ash actor from a bearer token.

  The token is read from `connect_info[:auth_token]`: the channels client's
  `authToken` option, sent in the `Sec-WebSocket-Protocol` header for
  websockets and the `Authorization` header for longpoll (enabled with
  `auth_token: true` on the endpoint's `socket/3`). It is deliberately not
  accepted as a connect param, which would put the credential in the query
  string.

  A missing or invalid token connects anonymously (actor `nil`).
  """
  @impl true
  def connect(_params, socket, connect_info) do
    actor =
      case BearerToken.user_from_token(connect_info[:auth_token]) do
        {:ok, user} -> user
        :error -> nil
      end

    {:ok, Absinthe.Phoenix.Socket.put_options(socket, context: %{actor: actor})}
  end

  @impl true
  def id(_socket), do: nil
end
