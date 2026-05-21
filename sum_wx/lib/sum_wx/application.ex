defmodule SumWx.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Supervisor.child_spec({SumWx.GUI, []}, restart: :temporary)
    ]

    opts = [strategy: :one_for_one, name: SumWx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
