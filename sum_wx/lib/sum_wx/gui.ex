defmodule SumWx.GUI do
  @moduledoc false

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    wx = :wx.new()

    frame = :wxFrame.new(wx, -1, ~c"Sum App", size: {420, 120})
    panel = :wxPanel.new(frame)

    input1 = :wxTextCtrl.new(panel, 101, ~c"")
    input2 = :wxTextCtrl.new(panel, 102, ~c"")

    plus_panel = :wxPanel.new(panel)
    eq_panel = :wxPanel.new(panel)
    result_panel = :wxPanel.new(panel)

    plus_label = :wxStaticText.new(plus_panel, -1, ~c"+")
    eq_label = :wxStaticText.new(eq_panel, -1, ~c"=")
    result_label = :wxStaticText.new(result_panel, -1, ~c"0")

    {_bw, bh} = :wxWindow.getBestSize(input1)
    :wxWindow.setMinSize(plus_panel, {24, bh})
    :wxWindow.setMinSize(eq_panel, {24, bh})
    :wxWindow.setMinSize(result_panel, {44, bh})

    center_plus = :wxBoxSizer.new(8)
    :wxSizer.add(center_plus, 0, 0, proportion: 1)
    :wxSizer.add(center_plus, plus_label, flag: 8192)
    :wxSizer.add(center_plus, 0, 0, proportion: 1)
    :wxPanel.setSizer(plus_panel, center_plus)

    center_eq = :wxBoxSizer.new(8)
    :wxSizer.add(center_eq, 0, 0, proportion: 1)
    :wxSizer.add(center_eq, eq_label, flag: 8192)
    :wxSizer.add(center_eq, 0, 0, proportion: 1)
    :wxPanel.setSizer(eq_panel, center_eq)

    center_result = :wxBoxSizer.new(8)
    :wxSizer.add(center_result, 0, 0, proportion: 1)
    :wxSizer.add(center_result, result_label, flag: 8192)
    :wxSizer.add(center_result, 0, 0, proportion: 1)
    :wxPanel.setSizer(result_panel, center_result)

    row = :wxBoxSizer.new(4)
    :wxSizer.add(row, input1, proportion: 1, flag: 16, border: 8)
    :wxSizer.add(row, plus_panel, flag: 16, border: 8)
    :wxSizer.add(row, input2, proportion: 1, flag: 16, border: 8)
    :wxSizer.add(row, eq_panel, flag: 16, border: 8)
    :wxSizer.add(row, result_panel, flag: 16, border: 8)

    root = :wxBoxSizer.new(8)
    :wxSizer.add(root, 0, 0, proportion: 1)
    :wxSizer.add(root, row, flag: 8192)
    :wxSizer.add(root, 0, 0, proportion: 1)

    :wxPanel.setSizer(panel, root)

    :wxTextCtrl.connect(input1, :command_text_updated)
    :wxTextCtrl.connect(input2, :command_text_updated)
    :wxFrame.connect(frame, :close_window)

    :wxFrame.show(frame)

    ui = %{
      wx: wx,
      frame: frame,
      input1: input1,
      input2: input2,
      result_label: result_label
    }

    {:ok, Map.merge(state, ui)}
  end

  @impl true
  def handle_info({:wx, _, _, _, {:wxCommand, :command_text_updated, _, _, _}}, state) do
    a = state.input1 |> :wxTextCtrl.getValue() |> parse_int()
    b = state.input2 |> :wxTextCtrl.getValue() |> parse_int()

    :wxStaticText.setLabel(state.result_label, Integer.to_string(a + b))
    {:noreply, state}
  end

  def handle_info({:wx, _, _, _, {:wxClose, :close_window}}, state) do
    :wxFrame.destroy(state.frame)
    :wx.destroy()
    {:stop, :normal, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp parse_int(chars) do
    chars
    |> to_string()
    |> String.trim()
    |> case do
      "" -> 0
      str ->
        case Integer.parse(str) do
          {num, ""} -> num
          _ -> 0
        end
    end
  end
end
