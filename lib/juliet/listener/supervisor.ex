defmodule Juliet.ListenerSupervisor do
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts)
  end

  def init(_opts) do

    listeners = Application.get_env(:juliet, :listeners, [])

    children = for listener <- listeners, do: child_spec(listener)

    opts = [strategy: :one_for_one, name: Juliet.ListenerSupervisor]
    supervise(children, opts)
  end

  defp child_spec({module, opts}) do
    {acceptors, opts} = Keyword.pop(opts, :acceptors, 100)
    protocol_opts     = Keyword.take(opts, [:starttls, :starttls_required, :certfile])
    transport_opts    = Keyword.take(opts, [:port])

    :ranch.child_spec(make_ref(), acceptors, :ranch_tcp, transport_opts, module, protocol_opts)
  end
end
