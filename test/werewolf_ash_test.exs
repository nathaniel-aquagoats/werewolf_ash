defmodule WerewolfAshTest do
  use ExUnit.Case
  doctest WerewolfAsh

  test "greets the world" do
    assert WerewolfAsh.hello() == :world
  end
end
