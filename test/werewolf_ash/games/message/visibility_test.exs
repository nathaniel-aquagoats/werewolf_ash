defmodule WerewolfAsh.Games.Message.VisibilityTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators
  import Ash.Expr

  alias Ash.Query
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Message
  alias WerewolfAsh.Games.Message.Visibility

  # message_test.exs already covers the full posting/reading matrix through
  # the `visible_to` action; this only checks that the Visibility expressions
  # themselves produce the right rows when applied directly with a query
  # filter, for one player of each kind that matters to the rule.
  setup do
    game = generate(game())
    villager = generate(player(game_id: game.id, role: :villager))
    wolf = generate(player(game_id: game.id, role: :werewolf))

    dead =
      generate(player(game_id: game.id, role: :villager)) |> Games.update_player!(%{alive: false})

    village_message = Games.send_message!(game.id, villager.id, :village, "village")
    wolves_message = Games.send_message!(game.id, wolf.id, :wolves, "wolves")

    %{
      villager: villager,
      wolf: wolf,
      dead: dead,
      village_message: village_message,
      wolves_message: wolves_message
    }
  end

  defp visible_message_ids(player_id) do
    Message
    |> Query.do_filter(Visibility.visible_to(expr(id == ^player_id)))
    |> Ash.read!()
    |> MapSet.new(& &1.id)
  end

  test "a living villager sees only the village channel", ctx do
    assert visible_message_ids(ctx.villager.id) == MapSet.new([ctx.village_message.id])
  end

  test "a living wolf sees both channels", ctx do
    assert visible_message_ids(ctx.wolf.id) ==
             MapSet.new([ctx.village_message.id, ctx.wolves_message.id])
  end

  test "a dead player sees both channels", ctx do
    assert visible_message_ids(ctx.dead.id) ==
             MapSet.new([ctx.village_message.id, ctx.wolves_message.id])
  end
end
