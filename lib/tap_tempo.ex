defmodule TapTempo do
  @moduledoc """
  Configure pools and queues like so:

  ```
  config :tap_tempo,
    pools: [
      {:my_pool, max_executions_per_second: 10},
      {:my_other_pool, max_executions_per_second: 1},
    ],
    queues: [
      {:important_queue, :my_pool, order: 1, timeout: 30_000},
      {:not_so_important_queue, :my_pool, order: 2, timeout: 30_000},
      {:any_other_queue, :my_other_pool, order: 1, timeout: 60_000}
    ]
  ```

  Then run it with:

  ```
  TapTempo.run(fn -> 1 + 1 end, :important_queue)
  # => 2
  ```
  """

  alias TapTempo.Queues
  alias TapTempo.Response
  alias TapTempo.Worker

  @doc """
  Sends a given function into a given queue and awaits for its
  execution.
  """
  @spec run(function(), atom()) :: {:error, Response.t()} | any()
  def run(lambda, queue_name) do
    with {:ok, {queue, pool_name, order: _order, timeout: timeout}} <-
           get_registered_queue(queue_name),
         {{:ok, {pool, _options}}, _pool_name} <- {get_registered_pool(pool_name), pool_name} do
      Queues.ingest(self(), lambda, queue, pool)
      Worker.nudge(pool)

      receive do
        {:lambda, response} ->
          response

        error ->
          {:error,
           %Response{
             type: :runtime,
             message: "TapTempo failed with: #{inspect(error, pretty: true)}."
           }}
      after
        timeout ->
          {:error,
           %Response{
             type: :timeout,
             message:
               "TapTempo timed out after #{timeout} miliseconds for queue #{queue_name} on the #{pool} pool."
           }}
      end
    else
      {:error, :queue_not_found} ->
        {:error,
         %Response{
           type: :configuration,
           message: "TapTempo failed with unregistered queue #{queue_name}."
         }}

      {{:error, :pool_not_found}, pool_name} ->
        {:error,
         %Response{
           type: :configuration,
           message: "TapTempo failed with unregistered pool #{pool_name} for queue #{queue_name}."
         }}
    end
  end

  @doc """
  Gets configuration data of a given queue.
  """
  @spec get_registered_queue(atom()) :: {:ok, {atom(), atom(), keyword()}} | {:error, atom()}
  def get_registered_queue(queue) do
    case Enum.find(registered_queues(), fn {found_queue, _pool, _options} ->
           queue == found_queue
         end) do
      {found_queue, pool, options} ->
        {:ok, {found_queue, pool, options}}

      _any ->
        {:error, :queue_not_found}
    end
  end

  @doc """
  Gets configuration data of a given pool.
  """
  @spec get_registered_pool(atom()) :: {:ok, {atom(), keyword()}} | {:error, atom()}
  def get_registered_pool(pool) do
    case Enum.find(registered_pools(), fn {found_pool, _options} -> pool == found_pool end) do
      {found_pool, options} ->
        {:ok, {found_pool, options}}

      _any ->
        {:error, :pool_not_found}
    end
  end

  @doc """
  Lits all queues of a given pool ordered by descending order.
  """
  @spec pool_queues_by_order(atom()) :: list(atom())
  def pool_queues_by_order(pool) do
    registered_queues()
    |> Stream.filter(fn {_queue, found_pool, _options} ->
      pool == found_pool
    end)
    |> Stream.map(fn {queue, _pool, order: order, timeout: _timeout} ->
      %{order: order, queue: queue}
    end)
    |> Enum.sort(&(&1[:order] <= &2[:order]))
    |> Enum.map(fn %{queue: queue} ->
      queue
    end)
  end

  @doc """
  All queues' configuration.
  """
  @spec registered_queues() :: list(atom()) | nil
  def registered_queues do
    Application.get_env(:tap_tempo, :queues, [])
  end

  @doc """
  All pools' configuration.
  """
  @spec registered_pools() :: list(atom()) | nil
  def registered_pools do
    Application.get_env(:tap_tempo, :pools, [])
  end
end
