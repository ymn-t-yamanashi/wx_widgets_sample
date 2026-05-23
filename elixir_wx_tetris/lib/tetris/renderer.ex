defmodule Tetris.Renderer do
  alias Tetris.Board

  @cell 0.09
  @x0 -0.95
  @y0 0.90

  @color_buffer_bit 0x4000

  def viewport_size, do: {900, 760}

  def draw_gl(state, w, h) do
    :gl.viewport(0, 0, w, max(h, 1))
    :gl.clearColor(0.08, 0.08, 0.11, 1.0)
    :gl.clear(@color_buffer_bit)

    draw_grid()
    draw_cells(state.board)
    draw_piece(state.current)
  end

  defp draw_grid do
    :gl.color3f(0.2, 0.2, 0.25)
    :gl.begin(0x0001)

    for y <- 0..Board.height() do
      yy = @y0 - y * @cell
      :gl.vertex2f(@x0, yy)
      :gl.vertex2f(@x0 + Board.width() * @cell, yy)
    end

    for x <- 0..Board.width() do
      xx = @x0 + x * @cell
      :gl.vertex2f(xx, @y0)
      :gl.vertex2f(xx, @y0 - Board.height() * @cell)
    end

    :gl.end()
  end

  defp draw_cells(board) do
    for {row, y} <- Enum.with_index(board), {type, x} <- Enum.with_index(row), not is_nil(type) do
      draw_block(x, y, type)
    end
  end

  defp draw_piece(piece) do
    for {x, y} <- Board.cells(piece), y >= 0 do
      draw_block(x, y, piece.type)
    end
  end

  defp draw_block(x, y, type) do
    {r, g, b} = color(type)
    x1 = @x0 + x * @cell
    y1 = @y0 - y * @cell
    x2 = x1 + @cell
    y2 = y1 - @cell

    :gl.color3f(r, g, b)
    :gl.begin(0x0007)
    :gl.vertex2f(x1, y1)
    :gl.vertex2f(x2, y1)
    :gl.vertex2f(x2, y2)
    :gl.vertex2f(x1, y2)
    :gl.end()
  end

  defp color(:i), do: {0.0, 0.86, 0.86}
  defp color(:o), do: {0.92, 0.85, 0.0}
  defp color(:t), do: {0.60, 0.25, 0.90}
  defp color(:s), do: {0.30, 0.82, 0.36}
  defp color(:z), do: {0.90, 0.28, 0.32}
  defp color(:j), do: {0.30, 0.40, 0.90}
  defp color(:l), do: {0.92, 0.54, 0.20}
end
