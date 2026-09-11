defmodule WerewolfAsh.Games.Message.Visibility do
  @moduledoc """
  The chat *read* rules as Ash expressions, defined once so the `visible_to`
  read action and the Message read policies (issue 27w.2) share them.

  Both functions build a filter over `Message` that looks the reader up
  through the message's `game.players`, so the reader must be a player in
  the message's game; inside that `exists`, the expression is evaluated
  against `Player` and `parent/1` refers to the message.
  """

  import Ash.Expr

  @doc """
  Evaluated against a `Player` inside `exists(game.players, ...)`: true when
  that player may read the parent message.

  Village is readable by every player of the game, the dead read every
  channel, and living werewolves read the wolves channel.
  """
  def player_may_read do
    expr(parent(channel) == :village or not alive or role == :werewolf)
  end

  @doc """
  Filter over `Message`: visible to the player matched by `player_match`, an
  expression evaluated against `Player`.

  The `visible_to` action passes `expr(id == ^player_id)`; a policy acting
  as a `User` can pass `expr(user_id == ^actor(:id))` and get the same rules.
  """
  def visible_to(player_match) do
    expr(exists(game.players, ^player_match and ^player_may_read()))
  end
end
