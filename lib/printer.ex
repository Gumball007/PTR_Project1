defmodule Printer do
    use GenServer

    def start(printer) do
        GenServer.start_link(__MODULE__, [], name: printer)
    end

    def init(_) do
        {:ok, nil}
    end

    def handle_cast({:send, message}, _) do
        Process.sleep(Enum.random(500..2000))
        IO.inspect "#{inspect self} -- #{message}"
        {:noreply, nil}
    end

    def handle_cast(:kill, state) do
        Process.exit(self(), :kill)
        {:noreply, state}
    end
end