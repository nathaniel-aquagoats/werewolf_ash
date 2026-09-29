defmodule WerewolfAsh.Games do
  @moduledoc """
  The werewolf game domain: games, their players, the day/night phases and the
  actions players take within them. All game rules live behind this domain's
  code interface; interfaces (GraphQL, scheduler) only call it.
  """

  use Ash.Domain,
    otp_app: :werewolf_ash,
    extensions: [AshGraphql.Domain]

  graphql do
    queries do
      # rule 6 - game(id): a caller with no seat, an unknown id, and no
      # token all get null with no errors entry (the Game read policy
      # filters; allow_nil? stays at its default true).
      get WerewolfAsh.Games.Game, :game, :read

      # rule 7 - myGames: no pagination arguments.
      list WerewolfAsh.Games.Game, :my_games, :mine
    end

    mutations do
      # rules 20-23 - createGame: the server invents the join code; no
      # client joinCode/ownerId.
      create WerewolfAsh.Games.Game, :create_game, :open do
        args [:name, :timezone, :day_start, :day_end]
      end

      # rule 27 - startGame: the game's id (AshGraphql's standard update
      # lookup); hide_inputs [:now] so a client cannot move the clock.
      update WerewolfAsh.Games.Game, :start_game, :start do
        hide_inputs [:now]
      end

      # rule 28 - updateGameSettings: the game's id, accepting exactly
      # :update_settings's own accept list.
      update WerewolfAsh.Games.Game, :update_game_settings, :update_settings

      # rule 24 - joinGame(joinCode).
      action WerewolfAsh.Games.Player, :join_game, :join_as_self do
        args [:join_code]
      end

      # rules 25-26 - leaveGame(gameId).
      action WerewolfAsh.Games.Player, :leave_game, :leave_as_self do
        args [:game_id]
      end

      # rules 14-16, 18 - vote/kill/investigate/protect/shoot(gameId,
      # targetId), each answering {result, errors} like a create/update
      # mutation.
      action WerewolfAsh.Games.Action, :vote, :cast_vote do
        args [:game_id, :target_id]
        error_location :in_result
      end

      action WerewolfAsh.Games.Action, :kill, :cast_kill do
        args [:game_id, :target_id]
        error_location :in_result
      end

      action WerewolfAsh.Games.Action, :investigate, :cast_investigation do
        args [:game_id, :target_id]
        error_location :in_result
      end

      action WerewolfAsh.Games.Action, :protect, :cast_protection do
        args [:game_id, :target_id]
        error_location :in_result
      end

      action WerewolfAsh.Games.Action, :shoot, :cast_shot do
        args [:game_id, :target_id]
        error_location :in_result
      end

      # rules 17, 17a - withdrawVote/withdrawProtection(gameId).
      action WerewolfAsh.Games.Action, :withdraw_vote, :withdraw_own_vote do
        args [:game_id]
        error_location :in_result
      end

      action WerewolfAsh.Games.Action, :withdraw_protection, :withdraw_own_protection do
        args [:game_id]
        error_location :in_result
      end
    end
  end

  resources do
    resource WerewolfAsh.Games.Game do
      define :create_game, action: :create
      define :update_game, action: :update
      define :update_game_settings, action: :update_settings
      define :finish_game, action: :finish, args: [:winner]
      define :destroy_game, action: :destroy
      define :get_game, action: :read, get_by: [:id]
      define :get_game_by_join_code, action: :read, get_by: [:join_code]
      define :list_games, action: :read
      define :open_game, action: :open
      define :my_games, action: :mine

      # Phase transitions. Each takes an optional `now` in the params map
      # (`Games.end_day!(game, %{now: dt})`); it defaults to the current time.
      define :start_game, action: :start
      define :end_day, action: :end_day
      define :end_night, action: :end_night
      define :resolve_hunter_deadline, action: :resolve_hunter_deadline
    end

    resource WerewolfAsh.Games.Player do
      define :add_player, action: :create, args: [:game_id, :user_id]
      define :join_game, action: :join, args: [:join_code, :user_id]
      define :update_player, action: :update
      define :remove_player, action: :destroy
      define :get_player, action: :read, get_by: [:id]
      define :list_players, action: :read
      define :list_living_players, action: :living_in_game, args: [:game_id]
      define :join_as_self, action: :join_as_self, args: [:join_code]
      define :leave_as_self, action: :leave_as_self, args: [:game_id]
    end

    resource WerewolfAsh.Games.Phase do
      define :create_phase, action: :create, args: [:game_id, :kind, :number]
      define :update_phase, action: :update
      define :destroy_phase, action: :destroy
      define :get_phase, action: :read, get_by: [:id]
      define :list_phases, action: :read
    end

    resource WerewolfAsh.Games.Action do
      define :create_action, action: :create, args: [:phase_id, :actor_id, :target_id, :type]
      define :create_kill_action, action: :kill, args: [:phase_id, :actor_id, :target_id]
      define :withdraw_action, action: :withdraw, args: [:phase_id, :actor_id, :type]
      define :update_action, action: :update
      define :get_action, action: :read, get_by: [:id]
      define :list_actions, action: :read
      define :cast_vote, action: :cast_vote, args: [:game_id, :target_id]
      define :cast_kill, action: :cast_kill, args: [:game_id, :target_id]
      define :cast_investigation, action: :cast_investigation, args: [:game_id, :target_id]
      define :cast_protection, action: :cast_protection, args: [:game_id, :target_id]
      define :cast_shot, action: :cast_shot, args: [:game_id, :target_id]
      define :withdraw_own_vote, action: :withdraw_own_vote, args: [:game_id]
      define :withdraw_own_protection, action: :withdraw_own_protection, args: [:game_id]
    end

    resource WerewolfAsh.Games.Message do
      define :send_message, action: :send_message, args: [:game_id, :author_id, :channel, :body]
      define :list_messages_visible_to, action: :visible_to, args: [:player_id]
    end
  end
end
