defmodule WerewolfAsh.Games.CallerResolution do
  @moduledoc """
  Shared resolution of "the caller's seat and the open phase" (rules 11-13,
  werewolf_ash-27w.3), reused by every GraphQL-facing generic action that
  names only a `game_id`: `Action`'s `:cast_vote`, `:cast_kill`,
  `:cast_investigation`, `:cast_protection`, `:cast_shot`,
  `:withdraw_own_vote`, `:withdraw_own_protection`, and `Player`'s
  `:leave_as_self`.

  Both functions read the game (`Games.get_game/2` with
  `load: [:current_phase]`) and the caller's own seat (`Games.list_players/1`
  filtered by `game_id`/`user_id`) authorized, as the caller - never with
  `authorize?: false`. An unknown game id and a caller with no seat are
  deliberately indistinguishable (rule 12): both come back as the same
  invalid-input error on `:game_id`, so no game id can be probed from the
  error alone.
  """

  alias Ash.Error.Changes.InvalidArgument
  alias WerewolfAsh.Games

  @doc "Resolves the caller's own seat in the named game (rules 11, 12)."
  @spec resolve_seat(Ash.UUID.t() | nil, map() | nil) ::
          {:ok, WerewolfAsh.Games.Player.t()} | {:error, Exception.t()}
  def resolve_seat(game_id, actor) do
    with {:ok, _game} <- fetch_game(game_id, actor) do
      fetch_seat(game_id, actor)
    end
  end

  @doc """
  Resolves the caller's own seat and the game's open phase (rules 11-13).
  Fails on `:game_id` both when the caller cannot read the game at all and
  when the game has no open phase right now (lobby or finished).
  """
  @spec resolve_seat_and_phase(Ash.UUID.t() | nil, map() | nil) ::
          {:ok, WerewolfAsh.Games.Player.t(), WerewolfAsh.Games.Phase.t()}
          | {:error, Exception.t()}
  def resolve_seat_and_phase(game_id, actor) do
    with {:ok, game} <- fetch_game(game_id, actor),
         {:ok, seat} <- fetch_seat(game_id, actor),
         {:ok, phase} <- fetch_open_phase(game) do
      {:ok, seat, phase}
    end
  end

  defp fetch_game(game_id, actor) do
    case Games.get_game(game_id, load: [:current_phase], actor: actor) do
      {:ok, game} -> {:ok, game}
      _ -> {:error, no_such_game()}
    end
  end

  defp fetch_seat(_game_id, nil), do: {:error, no_such_game()}

  defp fetch_seat(game_id, actor) do
    case Games.list_players(
           query: [filter: [game_id: game_id, user_id: actor.id]],
           actor: actor
         ) do
      {:ok, [seat]} -> {:ok, seat}
      _ -> {:error, no_such_game()}
    end
  end

  defp fetch_open_phase(%{current_phase: nil}), do: {:error, no_open_phase()}
  defp fetch_open_phase(%{current_phase: phase}), do: {:ok, phase}

  defp no_such_game do
    InvalidArgument.exception(
      field: :game_id,
      message: "no such game, or you have no seat in it"
    )
  end

  defp no_open_phase do
    InvalidArgument.exception(field: :game_id, message: "the game has no open phase right now")
  end
end
