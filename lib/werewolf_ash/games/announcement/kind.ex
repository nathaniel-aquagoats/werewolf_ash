defmodule WerewolfAsh.Games.Announcement.Kind do
  @moduledoc """
  What an announcement reports.

  - `:dawn` - the night's deaths, with roles.
  - `:dusk` - the lynch outcome, and whether night is starting.
  - `:shot` - a hunter's shot, the moment it lands.
  - `:game_over` - the winner of a finished game.
  """

  use Ash.Type.Enum, values: [:dawn, :dusk, :shot, :game_over]
end
