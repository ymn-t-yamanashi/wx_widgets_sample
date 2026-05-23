defmodule Tetris.Board do
  alias Tetris.Piece
  @width 10
  @height 20

  def width, do: @width
  def height, do: @height

  def empty do
    for _ <- 1..@height, do: for(_ <- 1..@width, do: nil)
  end

  def fits?(board, piece) do
    Enum.all?(cells(piece), fn {x, y} ->
      x >= 0 and x < @width and y < @height and (y < 0 or cell(board, x, y) == nil)
    end)
  end

  def place(board, piece) do
    Enum.reduce(cells(piece), board, fn {x, y}, acc ->
      if y < 0, do: acc, else: put_cell(acc, x, y, piece.type)
    end)
  end

  def clear_lines(board) do
    {kept, cleared} = Enum.split_with(board, fn row -> Enum.any?(row, &is_nil/1) end)
    filler = for _ <- 1..length(cleared), do: for(_ <- 1..@width, do: nil)
    {filler ++ kept, length(cleared)}
  end

  def cell(board, x, y), do: board |> Enum.at(y) |> Enum.at(x)

  defp put_cell(board, x, y, value) do
    List.update_at(board, y, fn row -> List.replace_at(row, x, value) end)
  end

  def cells(piece) do
    Piece.blocks(piece.type, piece.rot)
    |> Enum.map(fn {dx, dy} -> {piece.x + dx, piece.y + dy} end)
  end
end
