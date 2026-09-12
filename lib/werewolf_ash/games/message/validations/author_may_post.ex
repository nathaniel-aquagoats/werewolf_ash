defmodule WerewolfAsh.Games.Message.Validations.AuthorMayPost do
  @moduledoc """
  The chat *post* rules, checked when a message is sent:

    1. the author must be a player in the message's game;
    2. the author must be alive (the dead read everything, post nowhere);
    3. the wolves channel is only open to werewolves.

  Each rule fails with its own message so callers can tell them apart. The
  author is looked up without authorization: this is a game rule, not an
  access check, so it must not depend on what the actor may read.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias WerewolfAsh.Games.Player

  @impl true
  def validate(changeset, _opts, _context) do
    game_id = Changeset.get_attribute(changeset, :game_id)
    author_id = Changeset.get_attribute(changeset, :author_id)
    channel = Changeset.get_attribute(changeset, :channel)

    # Missing required attributes are reported by the action itself.
    if is_nil(game_id) or is_nil(author_id) or is_nil(channel) do
      :ok
    else
      author_id
      |> load_author()
      |> check(game_id, channel)
    end
  end

  defp load_author(author_id) do
    case Ash.get(Player, author_id, authorize?: false) do
      {:ok, player} -> player
      {:error, _} -> nil
    end
  end

  @doc """
  The pure rule: `:ok` or an error keyword list for the given author
  (`nil` when there is no such player), game and channel.
  """
  def check(author, game_id, channel)

  def check(%Player{game_id: game_id} = author, game_id, channel) do
    cond do
      not author.alive ->
        {:error, field: :author_id, message: "dead players cannot post"}

      channel == :wolves and author.role != :werewolf ->
        {:error,
         field: :channel, message: "only living werewolves may post in the wolves channel"}

      true ->
        :ok
    end
  end

  def check(_author_missing_or_elsewhere, _game_id, _channel) do
    {:error, field: :author_id, message: "must be a player in this game"}
  end
end
