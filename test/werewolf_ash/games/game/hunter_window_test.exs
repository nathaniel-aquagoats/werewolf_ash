defmodule WerewolfAsh.Games.Game.HunterWindowTest do
  @moduledoc """
  Direct unit test of `Game.HunterWindow`'s own contract (werewolf_ash-qss.7
  rule 1): `open/4` sets both fields together, `clear/2` nils both together.
  Reused by the lynch/dawn window-opening changes and by a landed shot's own
  change, each already covered end to end elsewhere.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias WerewolfAsh.Games.Game.HunterWindow

  describe "open/4" do
    test "sets pending_hunter_id to the given id and hunter_deadline_at to now + 1h" do
      game = generate(game())
      hunter = generate(player(game_id: game.id, role: :hunter))
      now = ~U[2026-06-15 20:00:00Z]

      assert {:ok, opened} = HunterWindow.open(game, hunter.id, now, authorize?: false)

      assert opened.pending_hunter_id == hunter.id
      assert DateTime.compare(opened.hunter_deadline_at, DateTime.add(now, 3600, :second)) == :eq
    end
  end

  describe "clear/2" do
    test "nils both pending_hunter_id and hunter_deadline_at" do
      game = generate(game())
      hunter = generate(player(game_id: game.id, role: :hunter))

      {:ok, opened} =
        HunterWindow.open(game, hunter.id, DateTime.utc_now(), authorize?: false)

      assert {:ok, cleared} = HunterWindow.clear(opened, authorize?: false)

      assert is_nil(cleared.pending_hunter_id)
      assert is_nil(cleared.hunter_deadline_at)
    end
  end
end
