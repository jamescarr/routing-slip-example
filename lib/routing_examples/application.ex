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
      # Routing Slip pattern components - start supervisor based on configured messenger
      routing_slip_supervisor(),
      # Start to serve requests, typically the last entry
      RoutingExamplesWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :routing_examples]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RoutingExamples.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Returns the appropriate supervisor based on the configured messenger
  defp routing_slip_supervisor do
    case Application.get_env(:routing_examples, :routing_slip_messenger) do
      RoutingExamples.RoutingSlip.Messenger.RabbitMQ ->
        RoutingExamples.RoutingSlip.Messenger.RabbitMQ.Supervisor

      _ ->
        # Default to PubSub supervisor (GenServer-based nodes)
        RoutingExamples.RoutingSlip.Supervisor
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RoutingExamplesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
