defmodule ElixirWxTetrisTest do
  use ExUnit.Case

  test "module loads" do
    assert Code.ensure_loaded?(ElixirWxTetris)
  end
end
