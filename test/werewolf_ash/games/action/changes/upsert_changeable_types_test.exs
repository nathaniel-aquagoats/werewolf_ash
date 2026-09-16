defmodule WerewolfAsh.Games.Action.Changes.UpsertChangeableTypesTest do
  use WerewolfAsh.DataCase, async: true

  alias Ash.Changeset
  alias WerewolfAsh.Games.Action
  alias WerewolfAsh.Games.Action.Changes.UpsertChangeableTypes

  defp changeset(type) do
    %Action{}
    |> Changeset.new()
    |> Changeset.change_attribute(:type, type)
  end

  describe "change/3" do
    test "marks a :vote changeset to upsert on the one_per_actor_per_phase_per_type identity" do
      changed = UpsertChangeableTypes.change(changeset(:vote), [], %{})

      assert changed.context[:private][:upsert?] == true
      assert changed.context[:private][:upsert_identity] == :one_per_actor_per_phase_per_type
      assert changed.context[:private][:upsert_fields] == [:target_id]
    end

    test "marks a :protect changeset to upsert the same way" do
      changed = UpsertChangeableTypes.change(changeset(:protect), [], %{})

      assert changed.context[:private][:upsert?] == true
    end

    test "leaves an :investigate or :shoot changeset unmarked (rule 5)" do
      refute UpsertChangeableTypes.change(changeset(:investigate), [], %{}).context[:private][
               :upsert?
             ]

      refute UpsertChangeableTypes.change(changeset(:shoot), [], %{}).context[:private][
               :upsert?
             ]
    end
  end
end
