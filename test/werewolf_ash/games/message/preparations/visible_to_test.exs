defmodule WerewolfAsh.Games.Message.Preparations.VisibleToTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Query
  alias Ash.UUID
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Message
  alias WerewolfAsh.Games.Message.Preparations.VisibleTo

  # Visibility itself is unit-tested directly; this only checks that the
  # preparation wires the `:player_id` query argument into it. The read
  # matrix by player kind lives in message_test.exs.
  setup do
    game = generate(game())
    villager = generate(player(game_id: game.id, role: :villager))
    message = Games.send_message!(game.id, villager.id, :village, "hi", authorize?: false)

    %{villager: villager, message: message}
  end

  defp prepared_query(player_id) do
    Message
    |> Query.new()
    |> Query.set_argument(:player_id, player_id)
    |> VisibleTo.prepare([], %{})
  end

  test "narrows the query to what the given player may read", ctx do
    assert [%{id: id}] = ctx.villager.id |> prepared_query() |> Ash.read!(authorize?: false)
    assert id == ctx.message.id
  end

  test "an unrecognized player id matches nothing" do
    assert UUID.generate() |> prepared_query() |> Ash.read!(authorize?: false) == []
  end
end
