defmodule Tetris.Input do
  @left 314
  @up 315
  @right 316
  @down 317
  @esc 27
  @space 32

  def to_action(%{key_code: @left}), do: :move_left
  def to_action(%{key_code: @right}), do: :move_right
  def to_action(%{key_code: @down}), do: :soft_drop
  def to_action(%{key_code: @up}), do: :rotate_cw
  def to_action(%{key_code: @space}), do: :hard_drop
  def to_action(%{key_code: @esc}), do: :quit

  def to_action(%{unicode_key: u}) when is_integer(u) do
    case [u] |> List.to_string() |> String.downcase() do
      "x" -> :rotate_cw
      "z" -> :rotate_ccw
      "p" -> :toggle_pause
      "r" -> :restart
      _ -> :noop
    end
  rescue
    _ -> :noop
  end

  def to_action(_), do: :noop
end
