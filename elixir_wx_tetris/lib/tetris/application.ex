defmodule Tetris.Application do
  use Application

  def start(_type, _args) do
    children =
      if Mix.env() == :test do
        [{Tetris.GameLoop, []}]
      else
        [{Tetris.GameLoop, []}, {Tetris.Window, []}]
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: Tetris.Supervisor)
  end
end
