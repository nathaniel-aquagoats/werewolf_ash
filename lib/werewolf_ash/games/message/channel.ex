defmodule WerewolfAsh.Games.Message.Channel do
  @moduledoc """
  Which chat channel a message belongs to.

  - `:village` - readable and postable by every living player.
  - `:wolves` - readable and postable by living werewolves only.

  Dead players can read both channels but post in neither.
  """

  use Ash.Type.Enum, values: [:village, :wolves]
end
