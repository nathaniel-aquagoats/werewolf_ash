defmodule WerewolfAsh.Games.Action.Validations.NoConsecutiveProtectTest do
  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias Ash.Seed
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Validations.NoConsecutiveProtect

  # Seeds a historic :protect row directly, bypassing every other
  # validation, so these tests isolate rule 4 from the rules that would
  # otherwise gate a real `:protect` action (day phase, bodyguard role...).
  defp seed_protect(phase, actor, target) do
    Seed.seed!(Action, %{
      phase_id: phase.id,
      actor_id: actor.id,
      target_id: target.id,
      type: :protect
    })
  end

  defp protect_changeset(phase, actor, target) do
    %Action{}
    |> Changeset.new()
    |> Changeset.change_attribute(:phase_id, phase.id)
    |> Changeset.change_attribute(:actor_id, actor.id)
    |> Changeset.change_attribute(:target_id, target.id)
  end

  describe "validate/3" do
    test "passes on a game's first-ever phase regardless of target" do
      game = generate(game())
      day1 = generate(phase(game_id: game.id, kind: :day, number: 1))
      actor = generate(player(game_id: game.id))
      target = generate(player(game_id: game.id))

      changeset = protect_changeset(day1, actor, target)

      assert NoConsecutiveProtect.validate(changeset, [], %{}) == :ok
    end

    test "passes when the target differs from the actor's immediately preceding day's target" do
      game = generate(game())
      day1 = generate(phase(game_id: game.id, kind: :day, number: 1))
      _night1 = generate(phase(game_id: game.id, kind: :night, number: 2))
      day2 = generate(phase(game_id: game.id, kind: :day, number: 3))
      actor = generate(player(game_id: game.id))
      x = generate(player(game_id: game.id))
      y = generate(player(game_id: game.id))

      seed_protect(day1, actor, x)

      changeset = protect_changeset(day2, actor, y)

      assert NoConsecutiveProtect.validate(changeset, [], %{}) == :ok
    end

    test "fails, on :target_id, when the target matches the immediately preceding day's target" do
      game = generate(game())
      day1 = generate(phase(game_id: game.id, kind: :day, number: 1))
      _night1 = generate(phase(game_id: game.id, kind: :night, number: 2))
      day2 = generate(phase(game_id: game.id, kind: :day, number: 3))
      actor = generate(player(game_id: game.id))
      x = generate(player(game_id: game.id))

      seed_protect(day1, actor, x)

      changeset = protect_changeset(day2, actor, x)

      assert {:error, error} = NoConsecutiveProtect.validate(changeset, [], %{})
      assert Keyword.fetch!(error, :field) == :target_id
    end

    test "passes for the same target again once a day has passed with a different target" do
      game = generate(game())
      day1 = generate(phase(game_id: game.id, kind: :day, number: 1))
      _night1 = generate(phase(game_id: game.id, kind: :night, number: 2))
      day2 = generate(phase(game_id: game.id, kind: :day, number: 3))
      _night2 = generate(phase(game_id: game.id, kind: :night, number: 4))
      day3 = generate(phase(game_id: game.id, kind: :day, number: 5))
      actor = generate(player(game_id: game.id))
      x = generate(player(game_id: game.id))
      y = generate(player(game_id: game.id))

      seed_protect(day1, actor, x)
      seed_protect(day2, actor, y)

      changeset = protect_changeset(day3, actor, x)

      assert NoConsecutiveProtect.validate(changeset, [], %{}) == :ok
    end

    test "passes on a game's first day phase when the game opened at night" do
      game = generate(game())
      _night1 = generate(phase(game_id: game.id, kind: :night, number: 1))
      day1 = generate(phase(game_id: game.id, kind: :day, number: 2))
      actor = generate(player(game_id: game.id))
      target = generate(player(game_id: game.id))

      changeset = protect_changeset(day1, actor, target)

      assert NoConsecutiveProtect.validate(changeset, [], %{}) == :ok
    end
  end
end
