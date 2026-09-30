defmodule WerewolfAsh.Games.Announcement.Death do
  @moduledoc """
  One announced death: the player, the role they held and how they died.
  Deliberately no relationship to `Player`, so an announcement can carry no
  later state.
  """

  use Ash.Resource,
    data_layer: :embedded,
    extensions: [AshGraphql.Resource]

  alias WerewolfAsh.Games.Announcement.Cause
  alias WerewolfAsh.Games.Player.Role

  graphql do
    type :announced_death
  end

  attributes do
    attribute :player_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :role, Role do
      public? true
    end

    attribute :cause, Cause do
      allow_nil? false
      public? true
    end
  end
end
