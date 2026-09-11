defmodule WerewolfAsh.Games.Message do
  @moduledoc """
  A chat message posted by a player into one of a game's channels.

  Rules (locked, see issue qss.12):

    * `:village` — every living player may post; everyone in the game may read.
    * `:wolves` — only living werewolves may post; living werewolves and the
      dead may read. Living non-wolves must never see it.
    * Both channels are open in every phase; dead players read everything and
      post nowhere.

  Posting is enforced by `send_message`'s validations; reading by the
  `visible_to` read action, whose filter lives in
  `WerewolfAsh.Games.Message.Visibility` so the read policies (issue 27w.2)
  can reuse the exact same expression. Messages are immutable, so there is
  only an `inserted_at`.
  """

  use Ash.Resource,
    otp_app: :werewolf_ash,
    domain: WerewolfAsh.Games,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "messages"
    repo WerewolfAsh.Repo

    references do
      reference :game, on_delete: :delete
      reference :author, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :send_message do
      primary? true
      accept [:game_id, :author_id, :channel, :body]

      validate WerewolfAsh.Games.Message.Validations.AuthorMayPost do
        only_when_valid? true
      end
    end

    read :visible_to do
      description """
      Messages the given player may read, oldest first: the village channel of
      their game, plus the wolves channel if they are dead or a living werewolf.
      A player id from another game (or an unknown one) simply sees nothing.
      """

      argument :player_id, :uuid do
        allow_nil? false
      end

      prepare WerewolfAsh.Games.Message.Preparations.VisibleTo
      prepare build(sort: [inserted_at: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :channel, WerewolfAsh.Games.Message.Channel do
      allow_nil? false
      public? true
    end

    attribute :body, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 2000, trim?: true
    end

    create_timestamp :inserted_at do
      public? true
    end
  end

  relationships do
    belongs_to :game, WerewolfAsh.Games.Game do
      allow_nil? false
      public? true
    end

    belongs_to :author, WerewolfAsh.Games.Player do
      allow_nil? false
      public? true
    end
  end
end
