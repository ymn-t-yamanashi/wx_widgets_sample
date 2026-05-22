defmodule Elixir3dGallery do
  @moduledoc """
  Elixir + :wx + OpenGL で動く 3D ミニギャラリー。
  """

  def start do
    Application.ensure_all_started(:elixir_3d_gallery)
  end
end
