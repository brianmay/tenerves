defmodule TenervesTest do
  use ExUnit.Case
  doctest Tenerves

  test "greets the world" do
    assert Tenerves.hello() == :world
  end
end
