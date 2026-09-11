defmodule WerewolfAsh.Games.Player.Role do
  use Ash.Type.Enum, values: [:werewolf, :villager, :seer, :bodyguard, :hunter]
end
