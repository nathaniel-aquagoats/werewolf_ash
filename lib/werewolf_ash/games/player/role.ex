defmodule WerewolfAsh.Games.Player.Role do
  @moduledoc """
  The role a player is secretly assigned for a game.

  - `:werewolf` - votes each night with the other werewolves to kill a player.
  - `:villager` - has no night action, only votes to lynch by day.
  - `:seer` - learns whether one chosen player is a werewolf each night.
  - `:bodyguard` - picks one player by day to protect from that night's kill.
  - `:hunter` - on death, gets a window to shoot one other player before dying.
  """

  use Ash.Type.Enum, values: [:werewolf, :villager, :seer, :bodyguard, :hunter]
end
