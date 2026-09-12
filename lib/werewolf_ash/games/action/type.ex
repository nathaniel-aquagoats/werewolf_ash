defmodule WerewolfAsh.Games.Action.Type do
  @moduledoc """
  The kind of action a player performs during a phase.

  - `:vote` - any living player's day vote to lynch another player.
  - `:wolf_vote` - a living werewolf's night vote to kill another player.
  - `:investigate` - the seer's night check of one player's role.
  - `:protect` - the bodyguard's pick of one player to shield that night.
  - `:shoot` - the hunter's shot at another player after dying.
  """

  use Ash.Type.Enum, values: [:vote, :wolf_vote, :investigate, :protect, :shoot]
end
