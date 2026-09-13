defmodule WerewolfAsh.Games.Message.PolicyTest do
  @moduledoc """
  Rules 10-11 (werewolf_ash-27w.2): `Message`'s read actions are filtered by
  the calling actor's own player seat (not just by whatever `player_id` a
  caller supplies), and `send_message` binds `author_id` to the caller.
  `message_test.exs` covers the post/read rule matrix itself through
  `authorize?: false`; this file exercises the *actor*-based policy layer
  those tests deliberately bypass.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias WerewolfAsh.Games

  defp actor_for(player), do: %{id: player.user_id}

  describe "rule 10 - Message read policy" do
    test "the bare :read action no longer returns wolves-channel messages to a non-wolf actor" do
      game = generate(game())
      wolf = generate(player(game_id: game.id, role: :werewolf))
      villager = generate(player(game_id: game.id, role: :villager))

      wolves_message =
        Games.send_message!(game.id, wolf.id, :wolves, "psst", authorize?: false)

      results = Ash.read!(Games.Message, actor: actor_for(villager))
      refute Enum.any?(results, &(&1.id == wolves_message.id))

      results = Ash.read!(Games.Message, actor: actor_for(wolf))
      assert Enum.any?(results, &(&1.id == wolves_message.id))
    end

    test "list_messages_visible_to never returns more than the caller's own actor-based visibility, regardless of player_id" do
      game = generate(game())
      wolf = generate(player(game_id: game.id, role: :werewolf))
      villager = generate(player(game_id: game.id, role: :villager))

      wolves_message =
        Games.send_message!(game.id, wolf.id, :wolves, "psst", authorize?: false)

      # A villager actor asking for the *wolf's* player_id must still only
      # see what the villager's own actor identity permits.
      results =
        Games.list_messages_visible_to!(wolf.id, actor: actor_for(villager))

      refute Enum.any?(results, &(&1.id == wolves_message.id))
    end
  end

  describe "rule 11 - Message send_message policy" do
    test "sending with author_id set to another player is forbidden with a policy-class error" do
      game = generate(game())
      author = generate(player(game_id: game.id))
      impersonator = generate(player(game_id: game.id))

      assert {:error, %Ash.Error.Forbidden{}} =
               Games.send_message(game.id, author.id, :village, "hi",
                 actor: actor_for(impersonator)
               )
    end

    test "sending with no actor at all is forbidden with a policy-class error" do
      game = generate(game())
      author = generate(player(game_id: game.id))

      assert {:error, %Ash.Error.Forbidden{}} =
               Games.send_message(game.id, author.id, :village, "hi")
    end

    test "sending as yourself into a channel your role doesn't allow is unaffected: still AuthorMayPost's ordinary error" do
      game = generate(game())
      villager = generate(player(game_id: game.id, role: :villager))

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Games.send_message(game.id, villager.id, :wolves, "hi", actor: actor_for(villager))

      assert %Ash.Error.Changes.InvalidAttribute{field: :channel} = error
    end
  end
end
