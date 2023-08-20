defmodule TapTempoTest do
  use ExUnit.Case

  alias TapTempo
  alias TapTempo.Support.TestingRegister

  setup do
    pools = [
      {:my_pool, max_executions_per_second: 10},
      {:my_other_pool, max_executions_per_second: 1}
    ]

    queues = [
      {:important_queue, :my_pool, order: 1, timeout: 30_000},
      {:not_so_important_queue, :my_pool, order: 2, timeout: 30_000},
      {:other_queue, :my_other_pool, order: 1, timeout: 60_000}
    ]

    Application.put_env(:tap_tempo, :pools, pools)
    Application.put_env(:tap_tempo, :queues, queues)

    Application.stop(:tap_tempo)
    Application.start(:tap_tempo)

    TapTempo.Logs.start_link([])
    TapTempo.Queues.start_link([])

    for {pool, _options} <- pools do
      TapTempo.Worker.start_link(pool)
    end

    TestingRegister.start_link([])

    [
      pools: pools,
      queues: queues
    ]
  end

  describe "pool/2" do
    test "Returns the execution output" do
      assert TapTempo.run(fn -> 1 + 1 end, :important_queue) == 2
    end

    test "It allows for concurrency. Doesn't matter if you got scheduled after, if you finish it first, you get the response first." do
      spawn(fn ->
        TapTempo.run(
          fn ->
            :timer.sleep(500)
            TestingRegister.write(500)
          end,
          :important_queue
        )
      end)

      spawn(fn ->
        TapTempo.run(
          fn ->
            :timer.sleep(400)
            TestingRegister.write(400)
          end,
          :important_queue
        )
      end)

      spawn(fn ->
        TapTempo.run(
          fn ->
            :timer.sleep(100)
            TestingRegister.write(100)
          end,
          :important_queue
        )
      end)

      spawn(fn ->
        TapTempo.run(
          fn ->
            TestingRegister.write(0)
          end,
          :important_queue
        )
      end)

      spawn(fn ->
        TapTempo.run(
          fn ->
            :timer.sleep(300)
            TestingRegister.write(300)
          end,
          :important_queue
        )
      end)

      :timer.sleep(600)

      assert [0, 100, 300, 400, 500] == TestingRegister.print_messages()
    end

    test "If the execution time is the same, then the response order follows the chronological order." do
      spawn(fn ->
        TapTempo.run(
          fn ->
            TestingRegister.write(1)
          end,
          :important_queue
        )
      end)

      spawn(fn ->
        TapTempo.run(
          fn ->
            TestingRegister.write(2)
          end,
          :important_queue
        )
      end)

      spawn(fn ->
        TapTempo.run(
          fn ->
            TestingRegister.write(3)
          end,
          :important_queue
        )
      end)

      spawn(fn ->
        TapTempo.run(
          fn ->
            TestingRegister.write(4)
          end,
          :important_queue
        )
      end)

      spawn(fn ->
        TapTempo.run(
          fn ->
            TestingRegister.write(5)
          end,
          :important_queue
        )
      end)

      :timer.sleep(100)

      assert [1, 2, 3, 4, 5] == TestingRegister.print_messages()
    end

    test "Higher relevance gets the response first." do
      spawn(fn ->
        TapTempo.run(
          fn ->
            TestingRegister.write(1)
          end,
          :not_so_important_queue
        )
      end)

      spawn(fn ->
        TapTempo.run(
          fn ->
            TestingRegister.write(2)
          end,
          :not_so_important_queue
        )
      end)

      spawn(fn ->
        TapTempo.run(
          fn ->
            TestingRegister.write(:important)
          end,
          :important_queue
        )
      end)

      spawn(fn ->
        TapTempo.run(
          fn ->
            TestingRegister.write(3)
          end,
          :not_so_important_queue
        )
      end)

      :timer.sleep(100)

      assert [:important, 1, 2, 3] == TestingRegister.print_messages()
    end

    test "If a high relevance request is taking long, concurrency should allow a lower relevance request to respond first." do
      spawn(fn ->
        TapTempo.run(
          fn ->
            :timer.sleep(300)
            TestingRegister.write(:important_but_slow)
          end,
          :important_queue
        )
      end)

      spawn(fn ->
        TapTempo.run(
          fn ->
            TestingRegister.write(:not_important_but_fast)
          end,
          :not_so_important_queue
        )
      end)

      :timer.sleep(400)

      assert [:not_important_but_fast, :important_but_slow] == TestingRegister.print_messages()
    end

    test "If a pool only allows for a maximum of 1 execution per second, 3 simultaneous executions must be 1 second appart from eachother." do
      spawn(fn ->
        TapTempo.run(
          fn ->
            TestingRegister.write(1)
          end,
          :other_queue
        )
      end)

      spawn(fn ->
        TapTempo.run(
          fn ->
            TestingRegister.write(2)
          end,
          :other_queue
        )
      end)

      spawn(fn ->
        TapTempo.run(
          fn ->
            TestingRegister.write(3)
          end,
          :other_queue
        )
      end)

      :timer.sleep(4000)

      {:ok,
       [
         {1, time_1},
         {2, time_2},
         {3, time_3}
       ]} = TestingRegister.read()

      assert 1000 + DateTime.diff(time_1, time_2, :millisecond) < 50
      assert 1000 + DateTime.diff(time_2, time_3, :millisecond) < 50
    end
  end

  describe "registered_pools/0" do
    test "Returns the configured pools.", %{pools: pools} do
      assert TapTempo.registered_pools() == pools
    end
  end

  describe "registered_queues/0" do
    test "Returns the configured queues.", %{queues: queues} do
      assert TapTempo.registered_queues() == queues
    end
  end
end
