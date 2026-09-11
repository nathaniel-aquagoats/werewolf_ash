defmodule WerewolfAshWeb.Plugs.BearerActor do
  @moduledoc """
  Sets the Ash actor from an `Authorization: Bearer <token>` request header
  using AshAuthentication's plug helpers (which also assign `current_user`).

  Must run before `AshGraphql.Plug`, which copies the actor into the Absinthe
  context. Requests without a valid token proceed anonymously (actor `nil`);
  policies decide what an anonymous actor may do.
  """

  @behaviour Plug

  alias AshAuthentication.Plug.Helpers

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn
    |> Helpers.retrieve_from_bearer(:werewolf_ash)
    |> Helpers.set_actor(:user)
  end
end
