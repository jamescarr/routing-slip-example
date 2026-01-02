defmodule RoutingExamples.Repo do
  use Ecto.Repo,
    otp_app: :routing_examples,
    adapter: Ecto.Adapters.Postgres
end
