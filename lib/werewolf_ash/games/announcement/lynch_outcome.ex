defmodule WerewolfAsh.Games.Announcement.LynchOutcome do
  @moduledoc """
  What a dusk announcement says about the vote: someone was `:lynched`, or it
  was `:no_lynch` (a tie, or no votes).
  """

  use Ash.Type.Enum, values: [:lynched, :no_lynch]
end
