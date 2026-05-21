defmodule SumWx do
  @moduledoc """
  Minimal wxWidgets sum app using Erlang/OTP :wx.
  """

  def start do
    Application.ensure_all_started(:sum_wx)
  end
end
