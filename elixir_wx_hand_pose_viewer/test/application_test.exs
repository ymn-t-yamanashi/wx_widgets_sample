defmodule ElixirWxHandPoseViewer.ApplicationTest do
  use ExUnit.Case, async: true

  test "app module is available" do
    assert function_exported?(ElixirWxHandPoseViewer.Application, :start, 2)
  end
end
