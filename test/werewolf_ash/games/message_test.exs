defmodule WerewolfAsh.Games.MessageTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Query
  alias Ash.UUID
  alias WerewolfAsh.Games
  alias WerewolfAsh.Games.Message

  require Query

  # One game with a player of each kind we care about, plus a player in some
  # other game to make sure nothing leaks across games.
  setup do
    game = generate(game())

    seat = fn role, alive ->
      player = generate(player(game_id: game.id, role: role))
      if alive, do: player, else: Games.update_player!(player, %{alive: false})
    end

    %{
      game: game,
      villager: seat.(:villager, true),
      wolf: seat.(:werewolf, true),
      dead_villager: seat.(:villager, false),
      dead_wolf: seat.(:werewolf, false),
      outsider: generate(player(role: :villager))
    }
  end

  defp post!(player, channel, body \\ "hello") do
    Games.send_message!(player.game_id, player.id, channel, body)
  end

  defp post(player, channel, body \\ "hello") do
    Games.send_message(player.game_id, player.id, channel, body)
  end

  defp visible_ids(player, opts \\ []) do
    player.id
    |> Games.list_messages_visible_to!(opts)
    |> Enum.map(& &1.id)
  end

  defp assert_rejected({:error, %Ash.Error.Invalid{errors: [error]}}, field, message) do
    assert %Ash.Error.Changes.InvalidAttribute{field: ^field, message: ^message} = error
  end

  describe "posting" do
    test "a living villager may post in village but not wolves", ctx do
      message = post!(ctx.villager, :village, "Good morning, village")

      assert message.channel == :village
      assert message.body == "Good morning, village"
      assert message.author_id == ctx.villager.id
      assert message.game_id == ctx.game.id
      assert %DateTime{} = message.inserted_at

      ctx.villager
      |> post(:wolves)
      |> assert_rejected(:channel, "only living werewolves may post in the wolves channel")
    end

    test "a living wolf may post in both channels", ctx do
      assert %{channel: :village} = post!(ctx.wolf, :village)
      assert %{channel: :wolves} = post!(ctx.wolf, :wolves)
    end

    test "a dead villager may post nowhere", ctx do
      for channel <- [:village, :wolves] do
        ctx.dead_villager
        |> post(channel)
        |> assert_rejected(:author_id, "dead players cannot post")
      end
    end

    test "a dead wolf may post nowhere, not even in wolves", ctx do
      for channel <- [:village, :wolves] do
        ctx.dead_wolf
        |> post(channel)
        |> assert_rejected(:author_id, "dead players cannot post")
      end
    end

    test "the author must be a player of the game", ctx do
      Games.send_message(ctx.game.id, ctx.outsider.id, :village, "psst")
      |> assert_rejected(:author_id, "must be a player in this game")

      Games.send_message(ctx.game.id, UUID.generate(), :village, "boo")
      |> assert_rejected(:author_id, "must be a player in this game")
    end

    test "only the two known channels exist", ctx do
      assert {:error, %Ash.Error.Invalid{errors: [%{field: :channel}]}} =
               post(ctx.villager, :whispers)
    end

    test "the body is 1..2000 characters after trimming", ctx do
      assert post!(ctx.villager, :village, "  padded  ").body == "padded"

      assert post!(ctx.villager, :village, String.duplicate("é", 2000)).body |> String.length() ==
               2000

      for body <- ["", "   ", String.duplicate("é", 2001)] do
        assert {:error, %Ash.Error.Invalid{errors: [%{field: :body}]}} =
                 post(ctx.villager, :village, body)
      end
    end
  end

  describe "reading" do
    setup ctx do
      # Alternate channels so the order test cannot pass by accident.
      village_1 = post!(ctx.villager, :village, "1 village")
      wolves_2 = post!(ctx.wolf, :wolves, "2 wolves")
      village_3 = post!(ctx.wolf, :village, "3 village")
      wolves_4 = post!(ctx.wolf, :wolves, "4 wolves")
      _elsewhere = post!(ctx.outsider, :village, "another game")

      %{
        village: [village_1.id, village_3.id],
        everything: [village_1.id, wolves_2.id, village_3.id, wolves_4.id]
      }
    end

    test "a living villager sees only the village channel", ctx do
      assert visible_ids(ctx.villager) == ctx.village
      assert visible_ids(ctx.villager, query: [filter: [channel: :wolves]]) == []
    end

    test "a living wolf sees village and wolves", ctx do
      assert visible_ids(ctx.wolf) == ctx.everything

      assert visible_ids(ctx.wolf, query: [filter: [channel: :wolves]]) ==
               Enum.take_every(tl(ctx.everything), 2)
    end

    test "a dead villager reads everything, wolves included", ctx do
      assert visible_ids(ctx.dead_villager) == ctx.everything
    end

    test "a dead wolf reads everything", ctx do
      assert visible_ids(ctx.dead_wolf) == ctx.everything
    end

    test "messages never cross games, and an unknown player sees nothing", ctx do
      assert [%{body: "another game"}] = Games.list_messages_visible_to!(ctx.outsider.id)
      assert Games.list_messages_visible_to!(UUID.generate()) == []
    end

    test "messages come back oldest first", ctx do
      messages = Games.list_messages_visible_to!(ctx.dead_wolf.id)

      assert Enum.map(messages, & &1.body) == ["1 village", "2 wolves", "3 village", "4 wolves"]
      assert messages == Enum.sort_by(messages, & &1.inserted_at, DateTime)
    end

    test "the author can be loaded", ctx do
      assert [%{author: %{id: author_id}} | _] =
               Games.list_messages_visible_to!(ctx.villager.id, load: :author)

      assert author_id == ctx.villager.id
    end
  end

  describe "deletion" do
    test "messages go with their game", ctx do
      post!(ctx.villager, :village)
      Games.destroy_game!(ctx.game)

      assert messages_in(ctx.game) == []
    end

    test "messages go with their author", ctx do
      post!(ctx.villager, :village, "mine")
      post!(ctx.wolf, :village, "theirs")
      Games.remove_player!(ctx.villager)

      assert [%{body: "theirs"}] = messages_in(ctx.game)
    end
  end

  defp messages_in(game) do
    Message
    |> Query.filter(game_id == ^game.id)
    |> Ash.read!()
  end
end
