defmodule Reader do
    use GenServer

  def start(url) do
    GenServer.start_link(__MODULE__, url: url)
  end

  def init([url: url]) do
    IO.puts "Connecting to stream..."
    HTTPoison.get!(url, [], [recv_timeout: :infinity, stream_to: self()])
    {:ok, nil}
  end

  defp load_bad_words do
    content = File.read!("./lib/bad_words.json")
    Jason.decode!(content)
  end

  defp filter_bad_words(message) do
    Enum.reduce(load_bad_words(), message, fn bad_word, filtered_message ->
      String.replace(filtered_message, bad_word, String.duplicate("*", String.length(bad_word)))
    end)
    # IO.puts()
  end

  def handle_info(%HTTPoison.AsyncChunk{chunk: chunk}, _state) do
    case Regex.run(~r/data: ({.+})\n\n$/, chunk) do
      [_, data] ->
        case Jason.decode(data) do
          {:ok, result} ->
              message_text = result["message"]["tweet"]["text"]
              filtered_message_text = filter_bad_words(message_text)
              GenServer.cast(:mediator, {:mediate, filtered_message_text})
          {:error, _} ->
              GenServer.cast(:mediator, :kill)
        end
      nil ->
        IO.puts "Don't know how to parse received chunk: \"#{chunk}\""
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

# ReaderSupervisor.start()
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
