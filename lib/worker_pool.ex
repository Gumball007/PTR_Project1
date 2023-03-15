defmodule PoolSupervisor do
    use Supervisor
  
    def start(num_workers) do
      Supervisor.start_link(__MODULE__, num_workers, name: __MODULE__)
    end
  
    def init(num_workers) do
      children = for i <- 0..num_workers - 1 do
        %{
          id: i,
          start: {Printer, :start, [:"printer_#{i}"]}
        }
      end
      Supervisor.init(children, strategy: :one_for_one, max_restarts: 10)
    end
end
