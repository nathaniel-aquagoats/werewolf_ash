defmodule WerewolfAsh.Games.Announcement.Cause do
  @moduledoc """
  How an announced player died: `:lynched` at dusk, `:killed` by the wolves in
  the night, or `:shot` by the hunter.
  """

  use Ash.Type.Enum, values: [:lynched, :killed, :shot]
end
