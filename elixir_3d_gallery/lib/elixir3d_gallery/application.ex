defmodule Elixir3dGallery.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Mix.env() == :test,
        do: [],
        else: [
          Supervisor.child_spec({Elixir3dGallery.GUI, []}, restart: :temporary)
        ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Elixir3dGallery.Supervisor)
  end
end
