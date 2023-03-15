defmodule Reader do
    use GenServer

  # Reader.start("localhost:4000/tweets/1")  
  def start(url) do
    # PoolSupervisor.start(3)
    # Mediator.start()
    GenServer.start_link(__MODULE__, url: url)
  end

  def init([url: url]) do
    IO.puts "Connecting to stream..."
    HTTPoison.get!(url, [], [recv_timeout: :infinity, stream_to: self()])
    {:ok, nil}
  end

  def handle_info(%HTTPoison.AsyncChunk{chunk: chunk}, _state) do
    case Regex.run(~r/data: ({.+})\n\n$/, chunk) do
      [_, data] ->
        # IO.inspect data
        case Jason.decode(data) do
            {:ok, result} ->
                GenServer.cast(:mediator, {:mediate, result["message"]["tweet"]["text"]})
            {:error, _} ->
                GenServer.cast(:mediator, :kill)
        end
      nil ->
        raise "Don't know how to parse received chunk: \"#{chunk}\""
    end
    {:noreply, nil}
    end

  def handle_info(%HTTPoison.AsyncStatus{} = status, _state) do
    IO.puts "Connection status: #{inspect status}"
    {:noreply, nil}
  end

  def handle_info(%HTTPoison.AsyncHeaders{} = headers, _state) do
    IO.puts "Connection headers: #{inspect headers}"
    {:noreply, nil}
  end
end

defmodule ReaderSupervisor do
  use Supervisor

  def start() do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    children = [
        %{
          id: :reader_1,
          start: {Reader, :start, ["localhost:4000/tweets/1"]}
        },
        %{
          id: :reader_2,
          start: {Reader, :start, ["localhost:4000/tweets/2"]}
        },
        %{
          id: :worker_pool,
          start: {PoolSupervisor, :start, [3]}
        },
        %{
          id: :mediator,
          start: {Mediator, :start, []}
        }
    ]
      Supervisor.init(children, strategy: :one_for_one, max_restarts: 10)
  end

end