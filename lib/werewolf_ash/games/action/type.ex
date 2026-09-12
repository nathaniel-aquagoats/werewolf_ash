defmodule WerewolfAsh.Games.Action.Type do
  @moduledoc """
  The kind of action a player performs during a phase.

  - `:vote` - any living player's day vote to lynch another player.
  - `:kill` - any living werewolf's night kill of another player; the pack's
    first landed kill each night is final.
  - `:investigate` - the seer's night check of one player's role.
  - `:protect` - the bodyguard's pick of one player to shield that night.
  - `:shoot` - the hunter's shot at another player after dying.
  """

  use Ash.Type.Enum, values: [:vote, :kill, :investigate, :protect, :shoot]
end
