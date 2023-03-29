defmodule Mediator do
    use GenServer

    def init(_) do
        {:ok, 0}
    end

    def start() do
        GenServer.start_link(__MODULE__, [], name: :mediator)
    end

    def handle_cast({:mediate, message}, state) do
        GenServer.cast(:"printer_#{state}", {:send, message})
        cond do
            state != 2 ->
                {:noreply, state + 1}
            state == 2 ->
                {:noreply, 0}
        end
    end

    def handle_cast(:kill, state) do
        IO.puts "Printer #{state} killed"
        GenServer.cast(:"printer_#{state}", :kill)
        cond do
            state != 2 ->
                {:noreply, state + 1}
            state == 2 ->
                {:noreply, 0}
        end
    end

end
