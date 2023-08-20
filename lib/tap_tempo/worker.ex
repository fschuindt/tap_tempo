defmodule TapTempo.Worker do
  @moduledoc """
  Lazy evaluation of the functions within the queues implemented as
  a GenServer. One instance per pool.

  In other words, upon instructed, this GenServer will consume the
  queues for its pool, aiming to respect the
  `:order` and `:max_executions_per_second` configurations.
  """

  alias Decimal, as: D
  alias TapTempo
  alias TapTempo.Logs
  alias TapTempo.Queues

  use GenServer

  @doc """
  Returns a Supervisor's child_spec. One instance per pool.
  """
  @spec child_specs() :: list({atom(), atom()})
  def child_specs do
    Enum.map(TapTempo.registered_pools(), fn {pool, _options} ->
      Supervisor.child_spec({__MODULE__, pool}, id: pool)
    end)
  end

  @doc """
  Starts the GenServer pool instance.
  """
  @spec start_link(atom()) ::
          {:ok, pid()} | :ignore | {:error, {:already_started, pid()} | term()}
  def start_link(pool) do
    case TapTempo.get_registered_pool(pool) do
      {:ok, {pool, max_executions_per_second: meps}} when is_integer(meps) ->
        GenServer.start_link(__MODULE__, pool, name: pool)

      _any ->
        raise "TapTempo failed to initialize #{pool}. Check configuration."
    end
  end

  @doc """
  A instruction to pop the pool's highest relevance queue and execute
  the function after the required anti-flood delay.

  Evaluation result is provided back via message-passing.
  """
  @spec nudge(atom()) ::
          {:noreply, new_state}
          | {:noreply, new_state, timeout() | :hibernate | {:continue, term()}}
          | {:stop, reason :: term(), new_state}
        when new_state: term()
  def nudge(pool) do
    GenServer.cast(pool, :nudge)
  end

  @impl true
  @spec init(atom()) :: {:ok, atom()}
  def init(pool) do
    {:ok, pool}
  end

  @impl true
  @spec handle_cast(:nudge, atom()) :: {:noreply, atom()}
  def handle_cast(:nudge, pool) do
    {:ok, {_pool, max_executions_per_second: meps}} = TapTempo.get_registered_pool(pool)
    do_nudge(pool, meps, Logs.requests_in_the_last_second(pool))

    {:noreply, pool}
  end

  @spec do_nudge(atom(), integer(), integer()) :: pid() | :ok
  defp do_nudge(pool, meps, requests_in_the_last_second)
       when requests_in_the_last_second < meps do
    execute(pool)
  end

  defp do_nudge(pool, meps, requests_in_the_last_second) do
    :timer.sleep(calculate_delay(meps, requests_in_the_last_second))
    execute(pool)
  end

  @spec execute(atom()) :: pid() | :ok
  defp execute(pool) do
    case Queues.pop_fifo(pool) do
      {:ok, {pid, lambda}} ->
        spawn_link(fn -> send(pid, {:lambda, lambda.()}) end)

      _any ->
        :ok
    end
  end

  @spec calculate_delay(integer(), integer()) :: integer()
  defp calculate_delay(meps, requests_in_the_last_second) do
    D.to_integer(D.round(do_calculate_delay(meps, requests_in_the_last_second)))
  end

  @spec do_calculate_delay(integer(), integer()) :: D.t()
  defp do_calculate_delay(meps, requests_in_the_last_second) do
    unit_delay = D.div_int(1_000, meps)
    extra_delay = D.mult(unit_delay, D.sub(requests_in_the_last_second, meps))

    if D.compare(extra_delay, D.new(0)) == :lt do
      unit_delay
    else
      D.add(unit_delay, extra_delay)
    end
  end
end
