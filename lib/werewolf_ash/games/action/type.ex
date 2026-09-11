defmodule WerewolfAsh.Games.Action.Type do
  use Ash.Type.Enum, values: [:vote, :wolf_vote, :investigate, :protect, :shoot]
end
