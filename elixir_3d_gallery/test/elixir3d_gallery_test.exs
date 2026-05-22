defmodule Elixir3dGalleryTest do
  use ExUnit.Case
  doctest Elixir3dGallery

  test "start function is available" do
    assert is_function(&Elixir3dGallery.start/0)
  end
end
