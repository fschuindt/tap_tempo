import Config

config :tap_tempo,
  pools: [
    {:example_pool, max_executions_per_second: 50}
  ],
  queues: [
    {:web, :example_pool, order: 1, timeout: 10_000},
    {:background, :example_pool, order: 2, timeout: 30_000},
  ]
