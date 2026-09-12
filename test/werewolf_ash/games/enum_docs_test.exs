defmodule WerewolfAsh.Games.EnumDocsTest do
  use ExUnit.Case, async: true

  @enum_modules [
    WerewolfAsh.Games.Player.Role,
    WerewolfAsh.Games.Phase.Kind,
    WerewolfAsh.Games.Message.Channel,
    WerewolfAsh.Games.Action.Type
  ]

  describe "@moduledoc" do
    for module <- @enum_modules do
      test "#{inspect(module)} has a non-empty module doc" do
        {:docs_v1, _annotation, _lang, _format, module_doc, _metadata, _docs} =
          Code.fetch_docs(unquote(module))

        assert %{"en" => doc} = module_doc
        assert is_binary(doc)
        assert String.trim(doc) != ""
      end
    end
  end
end
