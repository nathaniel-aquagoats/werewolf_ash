defmodule WerewolfAsh.Games.Game.Validations.KnownTimezone do
  @moduledoc """
  Rejects a time zone name the configured time zone database does not know.

  Only the value being written is checked, so the validation is safe to run
  atomically: a zone that is not changing was already validated when it was
  stored.
  """

  use Ash.Resource.Validation

  @impl true
  def init(opts) do
    if is_atom(opts[:attribute]) and not is_nil(opts[:attribute]) do
      {:ok, opts}
    else
      {:error, "`attribute` must be an atom, got: #{inspect(opts[:attribute])}"}
    end
  end

  @impl true
  def validate(changeset, opts, _context) do
    attribute = opts[:attribute]

    case Ash.Changeset.fetch_change(changeset, attribute) do
      {:ok, zone} -> check(zone, attribute)
      :error -> :ok
    end
  end

  # In a fully atomic update the new value lives in `atomics`. A literal can
  # still be checked here; only a real expression has to be refused.
  @impl true
  def atomic(changeset, opts, context) do
    attribute = opts[:attribute]

    case Keyword.fetch(changeset.atomics, attribute) do
      {:ok, zone} ->
        if Ash.Expr.expr?(zone) do
          {:not_atomic, "cannot check an atomic expression against the time zone database"}
        else
          check(zone, attribute)
        end

      :error ->
        validate(changeset, opts, context)
    end
  end

  # Any instant will do: shifting fails only when the zone is unknown.
  defp check(zone, attribute) when is_binary(zone) do
    case DateTime.shift_zone(~U[2000-01-01 00:00:00Z], zone) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, field: attribute, value: zone, message: "is not a known time zone"}
    end
  end

  # nil (or anything else) is left to the attribute's own type checks.
  defp check(_zone, _attribute), do: :ok
end
