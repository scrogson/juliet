defmodule Juliet do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(Juliet.ListenerSupervisor, [])
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
