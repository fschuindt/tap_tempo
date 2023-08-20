import Config

config :tap_tempo,
  pools: [
    {:a_given_third_party_api, max_executions_per_second: 10}
  ],
  queues: [
    {:important, :a_given_third_party_api, order: 1, timeout: 30_000},
    {:default, :a_given_third_party_api, order: 2, timeout: 30_000}
  ]
