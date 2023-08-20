defmodule TapTempo.Application do
  @moduledoc false

  use Application

  alias TapTempo.Logs
  alias TapTempo.Queues
  alias TapTempo.Worker

  def start(_type, _args) do
    children = [Queues, Logs] ++ Worker.child_specs()
    opts = [strategy: :one_for_one, name: TapTempo.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
