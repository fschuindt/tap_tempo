defmodule TapTempo.Logs do
  @moduledoc """
  Acts a simple memory-storage to keep track of the execution
  timestamps of each pool. This data is used to calculate the
  required delay in order to control the maximum number of requests
  per second.

  A maximum of @max_entries entries are kept in memory following a
  FIFO manner to discard the oldest.
  """

  alias TapTempo

  use GenServer

  @max_entries 256

  @doc """
  Starts the GenServer.
  """
  @spec start_link([]) :: {:ok, pid()} | :ignore | {:error, {:already_started, pid()} | term()}
  def start_link(_options) do
    GenServer.start_link(__MODULE__, init_pools(), name: __MODULE__)
  end

  @doc """
  Reads the storage data of a given pool.
  """
  @spec read(atom()) :: {:ok, list(DateTime.t())}
  def read(pool) do
    {:ok, GenServer.call(__MODULE__, {:read, pool})}
  end

  @doc """
  Adds a new timestamp to a given pool.
  """
  @spec write(atom()) ::
          {:noreply, new_state}
          | {:noreply, new_state, timeout() | :hibernate | {:continue, term()}}
          | {:stop, reason :: term(), new_state}
        when new_state: term()
  def write(pool) do
    GenServer.cast(__MODULE__, {:write, pool, DateTime.utc_now()})
  end

  @doc """
  Counts how many entries were inserted during the last second.
  """
  @spec requests_in_the_last_second(atom()) :: integer()
  def requests_in_the_last_second(pool) do
    with {:ok, log} <- read(pool),
         one_second_from_now <- DateTime.add(DateTime.utc_now(), -1),
         last_second_log <-
           Enum.filter(log, fn timestamp ->
             DateTime.compare(timestamp, one_second_from_now) == :gt
           end) do
      length(last_second_log)
    end
  end

  @spec init_pools() :: list(atom())
  defp init_pools do
    Enum.reduce(TapTempo.registered_pools(), %{}, fn {pool, _options}, acc ->
      Map.put(acc, pool, [])
    end)
  end

  @impl true
  @spec init([]) :: {:ok, []}
  def init(state) do
    {:ok, state}
  end

  @impl true
  @spec handle_call({:read, atom()}, {pid(), tag :: term()}, map()) :: {:reply, map(), map()}
  def handle_call({:read, pool}, _from, state) do
    {:reply, Map.get(state, pool), state}
  end

  @impl true
  @spec handle_cast({:write, atom(), DateTime.t()}, map()) :: {:noreply, map()}
  def handle_cast({:write, pool, timestamp}, state) do
    log = Map.get(state, pool)

    if length(log) < @max_entries do
      {:noreply, Map.put(state, pool, log ++ [timestamp])}
    else
      [_fifo | log] = log

      {:noreply, Map.put(state, pool, log ++ [timestamp])}
    end
  end
end
