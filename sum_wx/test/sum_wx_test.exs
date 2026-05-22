defmodule SumWxTest do
  use ExUnit.Case
  doctest SumWx

  test "start function is available" do
    assert is_function(&SumWx.start/0)
  end
end
