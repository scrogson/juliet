defmodule Juliet.StreamParser do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, self())
  end

  def parse(pid, data) do
    GenServer.cast(pid, {:parse, data})
  end

  def reset(pid) do
    GenServer.cast(pid, :reset)
  end

  def init(owner) do
    parser = :fxml_stream.new(owner, :infinity, [:no_gen_server])
    {:ok, {owner, parser}}
  end

  def handle_cast({:parse, data}, {owner, parser}) do
    parser = :fxml_stream.parse(parser, data)
    {:noreply, {owner, parser}}
  end

  def handle_cast(:reset, {owner, parser}) do
    parser = :fxml_stream.reset(parser)
    {:noreply, {owner, parser}}
  end
end
