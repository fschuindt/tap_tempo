defmodule TapTempo.Support.TestingRegister do
  @moduledoc false

  use GenServer

  @spec start_link([]) :: {:ok, pid()} | :ignore | {:error, {:already_started, pid()} | term()}
  def start_link(_options) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec read() :: {:ok, list({any(), DateTime.t()})}
  def read do
    {:ok, GenServer.call(__MODULE__, :read)}
  end

  @spec print_messages() :: list(any())
  def print_messages do
    {:ok, messages} = read()

    Enum.map(messages, fn {message, _timestamp} -> message end)
  end

  @spec write(any()) ::
          {:noreply, new_state}
          | {:noreply, new_state, timeout() | :hibernate | {:continue, term()}}
          | {:stop, reason :: term(), new_state}
        when new_state: term()
  def write(message) do
    GenServer.cast(__MODULE__, {:write, {message, DateTime.utc_now()}})
  end

  @spec reset() ::
          {:noreply, new_state}
          | {:noreply, new_state, timeout() | :hibernate | {:continue, term()}}
          | {:stop, reason :: term(), new_state}
        when new_state: term()
  def reset do
    GenServer.cast(__MODULE__, :reset)
  end

  @impl true
  @spec init([]) :: {:ok, []}
  def init(state) do
    {:ok, state}
  end

  @impl true
  @spec handle_call(:read, {pid(), tag :: term()}, list(tuple())) :: {:reply, map(), map()}
  def handle_call(:read, _from, state) do
    {:reply, state, state}
  end

  @impl true
  @spec handle_cast({:write, {any(), DateTime.t()}} | :reset, list(tuple())) :: {:noreply, map()}
  def handle_cast({:write, {message, timestamp}}, state) do
    {:noreply, state ++ [{message, timestamp}]}
  end

  def handle_cast(:reset, _state) do
    {:noreply, []}
  end
end
