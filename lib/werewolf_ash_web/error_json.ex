defmodule WerewolfAshWeb.ErrorJSON do
  alias Phoenix.Controller

  def render(template, _assigns) do
    %{errors: %{detail: Controller.status_message_from_template(template)}}
  end
end
