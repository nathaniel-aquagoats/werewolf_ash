defmodule WerewolfAsh.Games.Phase.Kind do
  @moduledoc """
  Which half of the wall-clock day/night cycle a phase represents.

  - `:day` - the village discusses and votes to lynch a player.
  - `:night` - werewolves, the seer and the bodyguard act in secret.
  """

  use Ash.Type.Enum, values: [:day, :night]
end
