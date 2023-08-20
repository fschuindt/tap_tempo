defmodule TapTempo.Queues do
  @moduledoc """
  Implements FIFO queues as a GenServer to store the requests by
  order of ingestion and relevance (config's `:order`).
  """

  alias TapTempo
  alias TapTempo.Logs

  use GenServer

  @doc """
  Starts the GenServer.
  """
  @spec start_link([]) :: {:ok, pid()} | :ignore | {:error, {:already_started, pid()} | term()}
  def start_link(_options) do
    GenServer.start_link(
      __MODULE__,
      %{
        pools: build_pools(),
        queues: build_queues(),
        pools_and_its_queues: build_pools_and_its_queues()
      },
      name: __MODULE__
    )
  end

  @doc """
  Intakes a new function to be executed at a given queue for a given
  pool.
  """
  @spec ingest(pid(), function(), atom(), atom()) :: :ok
  def ingest(pid, lambda, queue, pool) do
    GenServer.cast(__MODULE__, {:ingest, {pid, lambda, queue, pool}})
  end

  @doc """
  Pops (returns and remove from the queue) the next function to be
  executed following:

  1. Relevance: It's inversily proportional with the `:order`.
  Queues with high numbered orders have lower relevance.
  Where `order: 1` is the highest possible relevance.
  Check configuration.

  2. Order of ingestion: Chronological order of elements in the
  queue.
  """
  @spec pop_fifo(atom()) :: {:ok, {pid(), function()}}
  def pop_fifo(pool) do
    {:ok, GenServer.call(__MODULE__, {:pop_fifo, pool})}
  end

  @doc """
  Returns the queue of highest relevance containing elements.
  """
  @spec queue_to_pop_fifo(atom(), map(), map()) :: :empty | atom()
  def queue_to_pop_fifo(pool, queues, pools_and_its_queues) do
    case do_queue_to_pop_fifo(pool, queues, pools_and_its_queues) do
      {:found, queue} -> queue
      _any -> :empty
    end
  end

  @spec do_queue_to_pop_fifo(atom(), map(), map()) :: nil | {:found, atom()}
  defp do_queue_to_pop_fifo(pool, queues, pools_and_its_queues) do
    try do
      for queue <- Map.get(pools_and_its_queues, pool) do
        case Map.get(queues, queue) do
          [] -> nil
          _other -> throw({:found, queue})
        end
      end
    catch
      {:found, queue} -> {:found, queue}
    end
  end

  @spec build_pools() :: map()
  defp build_pools do
    Enum.reduce(TapTempo.registered_pools(), %{}, fn {pool, _options}, acc ->
      Map.put(acc, pool, [])
    end)
  end

  @spec build_queues() :: map()
  defp build_queues do
    Enum.reduce(TapTempo.registered_queues(), %{}, fn {queue, _pool, _options}, acc ->
      Map.put(acc, queue, [])
    end)
  end

  @spec build_pools_and_its_queues() :: map()
  defp build_pools_and_its_queues() do
    Enum.reduce(TapTempo.registered_pools(), %{}, fn {pool, _options}, acc ->
      Map.put(acc, pool, TapTempo.pool_queues_by_order(pool))
    end)
  end

  @impl true
  @spec init(any()) :: {:ok, any()}
  def init(state) do
    {:ok, state}
  end

  @impl true
  @spec handle_call({:pop_fifo, atom()}, {pid(), tag :: term()}, map()) ::
          {:reply, :empty | {pid(), function()}, map()}
  def handle_call(
        {:pop_fifo, pool},
        _from,
        %{queues: queues, pools_and_its_queues: pools_and_its_queues} = state
      ) do
    case queue_to_pop_fifo(pool, queues, pools_and_its_queues) do
      :empty ->
        {:reply, :empty, state}

      queue ->
        Logs.write(pool)
        [fifo | queue_tail] = Map.get(queues, queue)
        {:reply, fifo, Map.put(state, :queues, Map.put(queues, queue, queue_tail))}
    end
  end

  @impl true
  @spec handle_cast({:ingest, {pid(), function(), atom(), atom()}}, map()) :: {:noreply, map()}
  def handle_cast({:ingest, {pid, lambda, queue, _pool}}, %{queues: queues} = state) do
    delta_queues = Map.put(queues, queue, Map.get(queues, queue) ++ [{pid, lambda}])
    delta_state = Map.put(state, :queues, delta_queues)

    {:noreply, delta_state}
  end
end
