defmodule WerewolfAsh.Games.Game.Winner do
  @moduledoc """
  The team that won a finished game: the village (all wolves dead) or the
  wolves (at least as many living wolves as living non-wolves).
  """

  use Ash.Type.Enum, values: [:village, :wolves]
end
