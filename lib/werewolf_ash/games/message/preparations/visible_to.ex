defmodule WerewolfAsh.Games.Message.Preparations.VisibleTo do
  @moduledoc """
  Narrows a Message query to what the player named by the `:player_id`
  argument may read, using `WerewolfAsh.Games.Message.Visibility`.
  """

  use Ash.Resource.Preparation

  import Ash.Expr

  alias Ash.Query
  alias WerewolfAsh.Games.Message.Visibility

  @impl true
  def prepare(query, _opts, _context) do
    player_id = Query.get_argument(query, :player_id)

    Query.do_filter(query, Visibility.visible_to(expr(id == ^player_id)))
  end
end
