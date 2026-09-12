defmodule WerewolfAsh.Games.Game.Validations.KnownTimezoneTest do
  use ExUnit.Case, async: true

  import Ash.Expr

  alias Ash.Changeset
  alias WerewolfAsh.Games.Game
  alias WerewolfAsh.Games.Game.Validations.KnownTimezone

  describe "init/1" do
    test "accepts an atom attribute" do
      assert KnownTimezone.init(attribute: :timezone) == {:ok, [attribute: :timezone]}
    end

    test "rejects anything that is not an atom, or nil" do
      assert {:error, _reason} = KnownTimezone.init(attribute: "timezone")
      assert {:error, _reason} = KnownTimezone.init(attribute: nil)
    end
  end

  describe "validate/3" do
    test "a known zone being written passes" do
      changeset =
        %Game{}
        |> Changeset.new()
        |> Changeset.change_attribute(:timezone, "Europe/London")

      assert KnownTimezone.validate(changeset, [attribute: :timezone], %{}) == :ok
    end

    test "an unknown zone being written fails on that field" do
      changeset =
        %Game{}
        |> Changeset.new()
        |> Changeset.change_attribute(:timezone, "Not/AZone")

      assert {:error, error} = KnownTimezone.validate(changeset, [attribute: :timezone], %{})
      assert Keyword.fetch!(error, :field) == :timezone
    end

    test "an unknown zone already stored, but not being changed, passes" do
      # Matches the moduledoc's stated contract: only the value being written
      # is checked, so an existing bad value does not re-fail every update.
      changeset = Changeset.new(%Game{timezone: "Not/AZone"})

      assert KnownTimezone.validate(changeset, [attribute: :timezone], %{}) == :ok
    end
  end

  describe "atomic/3" do
    test "a literal atomic value is checked the same way as validate/3" do
      changeset =
        %Game{}
        |> Changeset.new()
        |> Changeset.atomic_update(:timezone, {:atomic, "Europe/Paris"})

      assert KnownTimezone.atomic(changeset, [attribute: :timezone], %{}) == :ok
    end

    test "an atomic expression cannot be checked against the time zone database" do
      changeset =
        %Game{}
        |> Changeset.new()
        |> Changeset.atomic_update(:timezone, {:atomic, ref(:owner_id)})

      assert {:not_atomic, _reason} = KnownTimezone.atomic(changeset, [attribute: :timezone], %{})
    end
  end
end
