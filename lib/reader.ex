defmodule Reader do
  use GenServer

  def start(url) do
    GenServer.start_link(__MODULE__, url: url)
  end

  def init(url: url) do
    IO.puts("Connecting to stream...")
    HTTPoison.get!(url, [], recv_timeout: :infinity, stream_to: self())
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
  end

  def handle_info(%HTTPoison.AsyncChunk{chunk: chunk}, _state) do
    case Regex.run(~r/data: ({.+})\n\n$/, chunk) do
      [_, data] ->
        case Jason.decode(data) do
          {:ok, result} ->
            message_text = result["message"]["tweet"]["text"]
            filtered_message_text = filter_bad_words(message_text)

            # Calculate sentiment score
            word_scores =
              HTTPoison.get!("http://localhost:4000/emotion_values").body
              |> String.split("\r\n")
              |> Enum.map(fn string ->
                [key, value] = String.split(string, "\t")
                {key, String.to_integer(value)}
                end)
              |> Enum.into(%{})

            sentiment_scores =
              String.split(filtered_message_text, " ")
                |> Enum.map(fn word ->
                  case Map.get(word_scores, word, 0) do
                    score when is_number(score) -> score
                    _ -> 0
                  end
                end)

            sentiment_score =
              if length(sentiment_scores) > 0 do
                  Enum.sum(sentiment_scores) / length(sentiment_scores)
              else
                  0
              end

            # Calculate engagement ratio
            followers = result["message"]["tweet"]["user"]["followers_count"]
            retweets = result["message"]["tweet"]["retweeted_status"]["retweet_count"] || 0
            favorites = result["message"]["tweet"]["retweeted_status"]["favorite_count"] || 0

            engagement_ratio =
              cond do
                followers == 0 ->
                  0
                followers > 0 ->
                  (favorites + retweets) / followers
              end

            GenServer.cast(
              :mediator,
              {:mediate,
                %{filtered_message_text: filtered_message_text,
                  engagement_ratio: engagement_ratio,
                  sentiment_score: sentiment_score}}
            )

          {:error, _} ->
            GenServer.cast(:mediator, :kill)
        end
      nil ->
        IO.puts("Don't know how to parse received chunk: \"#{chunk}\"")
    end

    {:noreply, nil}
  end

  def handle_info(%HTTPoison.AsyncStatus{} = status, _state) do
    IO.puts("Connection status: #{inspect(status)}")
    {:noreply, nil}
  end

  def handle_info(%HTTPoison.AsyncHeaders{} = headers, _state) do
    IO.puts("Connection headers: #{inspect(headers)}")
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
