defmodule RoutingExamples.RoutingSlip.Messenger.PubSub do
  @moduledoc """
  Phoenix.PubSub implementation of the Messenger behaviour.

  This is the default messenger for in-process communication,
  perfect for single-node deployments and development.

  Uses GenServer-based nodes supervised by DynamicSupervisor and
  discovered via Registry. Messages are routed directly via GenServer.cast.

  ## Configuration

  Uses the application's PubSub instance:

      config :routing_examples, :pubsub, RoutingExamples.PubSub

  """

  @behaviour RoutingExamples.RoutingSlip.Messenger

  alias RoutingExamples.RoutingSlip.Node

  @topic "routing_slip:updates"
  @registry RoutingExamples.RoutingSlip.NodeRegistry
  @supervisor RoutingExamples.RoutingSlip.NodeSupervisor

  defp pubsub do
    Application.get_env(:routing_examples, :pubsub, RoutingExamples.PubSub)
  end

  # ============================================================================
  # Event Broadcasting
  # ============================================================================

  @impl true
  def broadcast(event) do
    Phoenix.PubSub.broadcast(pubsub(), @topic, event)
  end

  @impl true
  def subscribe do
    Phoenix.PubSub.subscribe(pubsub(), @topic)
  end

  @impl true
  def unsubscribe do
    Phoenix.PubSub.unsubscribe(pubsub(), @topic)
  end

  # ============================================================================
  # Node Management
  # ============================================================================

  @impl true
  def create_node(name) when is_binary(name) and byte_size(name) > 0 do
    case DynamicSupervisor.start_child(@supervisor, {Node, name}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:error, {:already_exists, pid}}
      error -> error
    end
  end

  def create_node(_name), do: {:error, :invalid_name}

  @impl true
  def delete_node(name) when is_binary(name) do
    case Registry.lookup(@registry, name) do
      [{pid, _value}] ->
        DynamicSupervisor.terminate_child(@supervisor, pid)

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def list_nodes do
    Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.sort()
  end

  @impl true
  def node_exists?(name) do
    case Registry.lookup(@registry, name) do
      [{_pid, _value}] -> true
      [] -> false
    end
  end

  # ============================================================================
  # Message Routing
  # ============================================================================

  @impl true
  def route(destination, message) when is_binary(destination) do
    if node_exists?(destination) do
      Node.process_message(destination, message)
      :ok
    else
      {:error, {:node_not_found, destination}}
    end
  end
end
