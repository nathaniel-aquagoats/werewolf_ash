defmodule WerewolfAsh.Games.Announcement.Preparations.InOrder do
  @moduledoc """
  Creation order (`inserted_at`, `id` as tiebreak) with `game_over` always
  last. Not `announced_at`: a shot uses the wall clock while dawn and dusk use
  the injected `now`, so they can disagree.
  """

  use Ash.Resource.Preparation

  alias Ash.Query

  @impl true
  def prepare(query, _opts, _context) do
    Query.sort(query, game_over: :asc, inserted_at: :asc, id: :asc)
  end
end
