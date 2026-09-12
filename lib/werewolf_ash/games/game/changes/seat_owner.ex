defmodule WerewolfAsh.Games.Game.Changes.SeatOwner do
  @moduledoc """
  Adds the game's own `owner_id` to the `:players` argument before
  `manage_relationship` creates the seats, so `create_game` always seats its
  owner as a `Player` — whether or not a `players` argument was also
  supplied. If `players` also lists the owner's own `user_id`, the extra
  entry still reaches the `unique_user_per_game` identity as a duplicate
  seat, exactly like any other repeated `user_id`; this change does not
  special-case it.
  """

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, _context) do
    owner_id = Changeset.get_attribute(changeset, :owner_id)
    players = Changeset.get_argument(changeset, :players) || []

    Changeset.set_argument(changeset, :players, [%{user_id: owner_id} | players])
  end
end
