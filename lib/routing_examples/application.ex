defmodule RoutingExamples.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RoutingExamplesWeb.Telemetry,
      RoutingExamples.Repo,
      {DNSCluster, query: Application.get_env(:routing_examples, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: RoutingExamples.PubSub},
      # Start a worker by calling: RoutingExamples.Worker.start_link(arg)
      # {RoutingExamples.Worker, arg},
      # Start to serve requests, typically the last entry
      RoutingExamplesWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RoutingExamples.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RoutingExamplesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
