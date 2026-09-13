defmodule WerewolfAsh.Games.Game.RoleDistributionMode do
  @moduledoc """
  How a game's werewolf count is decided: `:automatic` from the seated
  player count (qss.3's own formula), or `:manual`, a fixed count the owner
  chooses via `manual_werewolf_count`.
  """

  use Ash.Type.Enum, values: [:automatic, :manual]
end
