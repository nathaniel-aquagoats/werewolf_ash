defmodule WerewolfAsh.Games.Game.Changes.AdvancePhaseTest do
  use WerewolfAsh.DataCase, async: true

  alias Ash.Changeset
  alias Ash.Error.Changes.InvalidAttribute
  alias WerewolfAsh.Games.Game
  alias WerewolfAsh.Games.Game.Changes.AdvancePhase
  alias WerewolfAsh.Games.Game.Clock
  alias WerewolfAsh.Generators

  defp game(attrs) do
    struct(
      %Game{timezone: "Etc/UTC", day_start: ~T[08:00:00], day_end: ~T[20:00:00], state: :day},
      attrs
    )
  end

  describe "init/1" do
    test "accepts each supported target" do
      assert AdvancePhase.init(to: :day) == {:ok, [to: :day]}
      assert AdvancePhase.init(to: :night) == {:ok, [to: :night]}
      assert AdvancePhase.init(to: :by_clock) == {:ok, [to: :by_clock]}
    end

    test "rejects anything else" do
      assert {:error, _reason} = AdvancePhase.init(to: :sideways)
    end
  end

  # Built via Ash.Changeset.for_update, which runs the action's declared
  # changes (including AdvancePhase) without touching the database — the
  # after_action hook that opens/closes phases only fires on Ash.update!.
  describe "change/3" do
    test "moves to a fixed target and computes its boundary from the Clock" do
      game = game(state: :day)
      now = ~U[2026-01-01 12:00:00Z]

      changeset = Changeset.for_update(game, :end_day, %{now: now}, authorize?: false)

      assert changeset.valid?
      assert Changeset.get_attribute(changeset, :state) == :night
      assert {:ok, expected_ends_at} = Clock.next_boundary(game, :night, now)

      # cast to :utc_datetime_usec on the way into the changeset, so compare
      # the instant rather than the raw struct precision.
      actual_ends_at = Changeset.get_attribute(changeset, :phase_ends_at)
      assert DateTime.compare(actual_ends_at, expected_ends_at) == :eq
    end

    test "resolves :by_clock from the game's own window" do
      # `:start` now also runs `ActorIsOwner`/`MinimumPlayers` (rules 8-9),
      # which query the database, so this one test needs a real persisted
      # game with an owner actor and enough seated players to stay valid.
      owner = Generators.generate(Generators.user())

      game =
        Generators.generate(
          Generators.game(owner_id: owner.id, day_start: ~T[22:00:00], day_end: ~T[06:00:00])
        )

      Generators.generate_many(Generators.player(game_id: game.id), 4)

      now = ~U[2026-01-01 23:00:00Z]

      changeset = Changeset.for_update(game, :start, %{now: now}, actor: owner)

      assert {:ok, expected_kind} = Clock.window_at(game, now)
      assert changeset.valid?
      assert Changeset.get_attribute(changeset, :state) == expected_kind
    end

    test "an unknown time zone fails the changeset with a :timezone error" do
      # A stored zone the KnownTimezone validation would have already
      # rejected on write; AdvancePhase's own defensive check is what is
      # under test here, so the bad value is injected directly.
      game = game(state: :day, timezone: "Not/AZone")
      now = ~U[2026-01-01 12:00:00Z]

      changeset = Changeset.for_update(game, :end_day, %{now: now}, authorize?: false)

      refute changeset.valid?
      assert [%InvalidAttribute{field: :timezone}] = changeset.errors
    end
  end
end
