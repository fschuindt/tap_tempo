# TapTempo

A concurrency-friendly, eager-evaluated, BEAM-wide function call rate limiter.

Adds virtual bottleneck to functions, so it respects a set of preconfigured limits.

## Installation

**Note:** This package isn't yet published to Hex.pm.

Add `:tap_tempo` to the list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tap_tempo, "~> 0.1.0"}
  ]
end
```

## About

It works based on two concepts, pools and queues.

Pools are configurable bottlenecks:
- `{:salesforce_api, max_executions_per_second: 50}`
- `{:stripe_api, max_executions_per_second: 10}`

Each pool has one or more queues. Each queue represents a distinct priority within that pool:
```elixir
config :tap_tempo,
  pools: [
    {:salesforce_api, max_executions_per_second: 50}
  ],
  queues: [
    {:web, :salesforce_api, order: 1, timeout: 10_000},
    {:background, :salesforce_api, order: 2, timeout: 30_000},
  ]
```

- `order:` The order of priority for that queue.
- `timemout:` How long to wait for that call to respond in milliseconds.

Usage:
```elixir
TapTempo.run(fn -> IO.puts("Hello world") end, :web)
TapTempo.run(fn -> IO.puts("Hello there") end, :background)
```

`TapTempo.run/2` returns whatever the given function returns, **or** `{:error, TapTempo.Response.t()}` when the timeout is reached before the function ever returned. Example: `{:error, %TapTempo.Response{type: :timeout, message: "TapTempo timed out after 30000 miliseconds for queue background on the salesforce_api pool."}}`.

If your system ever gets close to the configured limit, executions will experience an articial delay, just enough to keep it under. They will be evaluated following the chronological order of ingestion (FIFO), however, queues with lower `order` will always be put ahead.

As long as the system is under the limit, all executions are not only eagerly evaluated, but also concurrent:
```elixir
TapTempo.run(fn -> :time.sleep(1000); IO.puts("Slow function") end)
TapTempo.run(fn -> IO.puts("Fast function") end)

# Fast function
# Slow function
```

## ToDo
- [ ] Multiple pools. Some APIs have two different limits. (E.g. Per hour, per minute)
- [ ] Publish package.

## License

This library is distributed as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
