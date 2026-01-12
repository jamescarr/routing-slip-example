defmodule RoutingExamples.RoutingSlip.Messenger.RabbitMQ.Supervisor do
  @moduledoc """
  Supervisor for the RabbitMQ Messenger components.

  Supervises:
  - NodeTracker Agent (tracks registered node names)
  - Connection GenServer (maintains AMQP connection)
  - ConsumerRegistry (for tracking Broadway consumers by node name)
  - ConsumerSupervisor (DynamicSupervisor for Broadway node consumers)
  """
  use Supervisor

  alias RoutingExamples.RoutingSlip.Messenger.RabbitMQ

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Agent for tracking registered node names
      %{
        id: RabbitMQ.NodeTracker,
        start: {Agent, :start_link, [fn -> MapSet.new() end, [name: RabbitMQ.NodeTracker]]}
      },

      # Registry for looking up Broadway consumers by node name
      {Registry, keys: :unique, name: RabbitMQ.ConsumerRegistry},

      # Registry for looking up EventsListeners by subscriber pid
      {Registry, keys: :unique, name: RabbitMQ.ListenersRegistry},

      # AMQP Connection manager
      RabbitMQ.Connection,

      # DynamicSupervisor for node consumers (Broadway pipelines)
      {DynamicSupervisor, name: RabbitMQ.ConsumerSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
