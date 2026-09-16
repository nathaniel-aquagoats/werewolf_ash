defmodule WerewolfAsh.Games.Action.Changes.UpsertChangeableTypes do
  @moduledoc """
  Marks a `:create` changeset for `type: :vote` or `type: :protect` to
  upsert on the `one_per_actor_per_phase_per_type` identity, replacing the
  existing row's `target_id` in place instead of being refused by that
  identity's unique index — rules 1 and 2, the "recast" behaviour. Every
  other `type` (`:investigate`, `:shoot`) is left unmarked, so a second
  attempt at one of those still refuses outright, unchanged (rule 5).

  `Ash.Changeset.for_create/4` runs an action's declared `change`s before
  `Ash.create/2` ever reaches the data layer; the data layer then derives
  whether, and how, to upsert from `changeset.context[:private]`, falling
  back to the action's own static `upsert?`/`upsert_identity`/
  `upsert_fields` only when the context does not set them
  (`deps/ash/lib/ash/actions/create/create.ex:137-156`). So marking the
  context conditionally here, rather than declaring a static `upsert?` on
  `:create` itself, is enough to make `:vote`/`:protect` upsert while
  leaving every other type's `:create` call untouched.
  """

  use Ash.Resource.Change

  alias Ash.Changeset

  @changeable_types [:vote, :protect]

  @impl true
  def change(changeset, _opts, _context) do
    if Changeset.get_attribute(changeset, :type) in @changeable_types do
      Changeset.set_context(changeset, %{
        private: %{
          upsert?: true,
          upsert_identity: :one_per_actor_per_phase_per_type,
          upsert_fields: [:target_id]
        }
      })
    else
      changeset
    end
  end
end
