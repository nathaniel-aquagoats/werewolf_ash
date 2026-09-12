defmodule WerewolfAsh.Mailer do
  @moduledoc """
  The application's `Swoosh.Mailer`.

  The backing adapter is environment-specific config (see `config/*.exs`): a
  real, network-based adapter in `:prod`, a non-network one in `:dev`/`:test`.
  """

  use Swoosh.Mailer, otp_app: :werewolf_ash
end
