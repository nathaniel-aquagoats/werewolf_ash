defmodule WerewolfAsh.Games.Game.Changes.GenerateJoinCodeTest do
  @moduledoc """
  Direct unit tests for the join-code change (rules 22-23,
  werewolf_ash-27w.3): candidate selection against a changeset, plus the
  random path. `Games.open_game/2`'s own tests exercise the whole action.
  """

  use WerewolfAsh.DataCase, async: true

  import WerewolfAsh.Generators

  alias Ash.Changeset
  alias WerewolfAsh.Games.Game
  alias WerewolfAsh.Games.Game.Changes.GenerateJoinCode

  defp changeset(opts) do
    owner = generate(user())
    Changeset.for_create(Game, :open, %{name: "Test Game"}, [actor: owner] ++ opts)
  end

  describe "change/3" do
    test "takes the first candidate not already taken by another game" do
      generate(game(join_code: "TAKEN1"))

      changeset =
        [context: %{join_code_candidates: ["TAKEN1", "FREE01"]}]
        |> changeset()
        |> GenerateJoinCode.change([], %{})

      assert Changeset.get_attribute(changeset, :join_code) == "FREE01"
    end

    test "fails on :join_code once every candidate is taken" do
      taken = for n <- 1..10, do: "TAKEN#{n}"
      Enum.each(taken, &generate(game(join_code: &1)))

      changeset =
        [context: %{join_code_candidates: taken}]
        |> changeset()
        |> GenerateJoinCode.change([], %{})

      refute changeset.valid?
      assert Enum.any?(changeset.errors, &(&1.field == :join_code))
    end

    test "with no context candidates, draws a random 6-character code from the alphabet" do
      changeset = [] |> changeset() |> GenerateJoinCode.change([], %{})
      code = Changeset.get_attribute(changeset, :join_code)

      assert String.length(code) == 6
      assert code =~ ~r/^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]+$/
    end
  end

  describe "random_code/0" do
    test "returns a 6-character code drawn from the look-alike-free alphabet" do
      code = GenerateJoinCode.random_code()

      assert String.length(code) == 6
      assert code =~ ~r/^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]+$/
    end
  end
end
