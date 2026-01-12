defmodule RoutingExamples.RoutingSlip.Messenger.RabbitMQ do
  @moduledoc """
  RabbitMQ implementation of the Messenger behaviour.

  Uses AMQP for publishing messages and Broadway for consuming.

  ## Architecture

  - **Messages Exchange** (topic): Routes messages to node queues by routing key
  - **Events Exchange** (fanout): Broadcasts UI events to all subscribers
  - **Node Queues**: Each node gets a queue bound to the messages exchange
  - **Broadway Consumers**: Each node has a Broadway pipeline consuming its queue

  ## Configuration

      config :routing_examples, RoutingExamples.RoutingSlip.Messenger.RabbitMQ,
        connection: [host: "localhost", port: 5672, ...],
        messages_exchange: "routing_slip.messages",
        events_exchange: "routing_slip.events"

  ## Documentation

  - AMQP: https://hexdocs.pm/amqp/
  - Broadway: https://hexdocs.pm/broadway/
  - BroadwayRabbitMQ: https://hexdocs.pm/broadway_rabbitmq/
  """

  @behaviour RoutingExamples.RoutingSlip.Messenger

  alias RoutingExamples.RoutingSlip.Messenger.RabbitMQ.{Connection, EventsListener, NodeConsumer}

  require Logger

  @consumer_supervisor __MODULE__.ConsumerSupervisor
  @listeners_registry __MODULE__.ListenersRegistry

  # Agent for tracking registered nodes (started by Supervisor)
  @node_tracker __MODULE__.NodeTracker

  # ============================================================================
  # Event Broadcasting
  # ============================================================================

  @impl true
  def broadcast(event) do
    case Connection.get_channel() do
      {:ok, channel} ->
        payload = encode_event(event)
        AMQP.Basic.publish(channel, Connection.events_exchange(), "", payload)

      {:error, :not_connected} ->
        Logger.warning("[RabbitMQ] Cannot broadcast - not connected")
        {:error, :not_connected}
    end
  end

  @impl true
  def subscribe do
    subscriber = self()

    # Check if already subscribed
    case Registry.lookup(@listeners_registry, subscriber) do
      [{_pid, _}] ->
        # Already subscribed
        :ok

      [] ->
        # Start a new EventsListener for this subscriber
        case EventsListener.start_link(subscriber: subscriber) do
          {:ok, listener_pid} ->
            # Register the listener so we can find it later for unsubscribe
            Registry.register(@listeners_registry, subscriber, listener_pid)
            Logger.debug("[RabbitMQ] Subscriber #{inspect(subscriber)} connected to events")
            :ok

          {:error, reason} ->
            Logger.error("[RabbitMQ] Failed to start events listener: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @impl true
  def unsubscribe do
    subscriber = self()

    case Registry.lookup(@listeners_registry, subscriber) do
      [{_reg_pid, listener_pid}] ->
        # Stop the listener
        EventsListener.stop(listener_pid)
        # Unregister
        Registry.unregister(@listeners_registry, subscriber)
        Logger.debug("[RabbitMQ] Subscriber #{inspect(subscriber)} disconnected from events")
        :ok

      [] ->
        # Not subscribed
        :ok
    end
  end

  # ============================================================================
  # Node Management
  # ============================================================================

  @impl true
  def create_node(name) when is_binary(name) and byte_size(name) > 0 do
    # Check if node already exists
    if node_exists?(name) do
      {:error, {:already_exists, name}}
    else
      case Connection.get_channel() do
        {:ok, channel} ->
          queue_name = node_queue_name(name)
          routing_key = node_routing_key(name)

          # Declare queue and bind to exchange
          {:ok, _} = AMQP.Queue.declare(channel, queue_name, durable: false, auto_delete: true)
          :ok = AMQP.Queue.bind(channel, queue_name, Connection.messages_exchange(), routing_key: routing_key)

          # Start Broadway consumer for this node
          # Note: Broadway starts its own supervision tree, so we just call start_link
          case NodeConsumer.start_link(node_name: name) do
            {:ok, _pid} ->
              # Track the node
              track_node(name)

              Logger.info("[RabbitMQ] Node '#{name}' created with Broadway consumer")

              # Broadcast node created event
              broadcast({:node_created, name})

              {:ok, name}

            {:error, reason} ->
              # Clean up the queue if consumer failed to start
              AMQP.Queue.delete(channel, queue_name)
              Logger.error("[RabbitMQ] Failed to start consumer for '#{name}': #{inspect(reason)}")
              {:error, {:consumer_failed, reason}}
          end

        {:error, :not_connected} ->
          {:error, :not_connected}
      end
    end
  end

  def create_node(_name), do: {:error, :invalid_name}

  @impl true
  def delete_node(name) when is_binary(name) do
    # Stop the Broadway consumer first
    case NodeConsumer.stop(name) do
      :ok ->
        Logger.debug("[RabbitMQ] Stopped consumer for '#{name}'")

      {:error, :not_found} ->
        Logger.debug("[RabbitMQ] No consumer running for '#{name}'")
    end

    # Delete queue (if connection available)
    case Connection.get_channel() do
      {:ok, channel} ->
        queue_name = node_queue_name(name)
        AMQP.Queue.delete(channel, queue_name)

      {:error, :not_connected} ->
        Logger.warning("[RabbitMQ] Cannot delete queue - not connected")
    end

    # Untrack the node regardless
    untrack_node(name)

    Logger.info("[RabbitMQ] Node '#{name}' deleted")
    :ok
  end

  @impl true
  def list_nodes do
    get_tracked_nodes()
  end

  @impl true
  def node_exists?(name) do
    name in get_tracked_nodes()
  end

  # ============================================================================
  # Message Routing
  # ============================================================================

  @impl true
  def route(destination, message) when is_binary(destination) do
    case Connection.get_channel() do
      {:ok, channel} ->
        routing_key = node_routing_key(destination)
        payload = Jason.encode!(message)

        AMQP.Basic.publish(
          channel,
          Connection.messages_exchange(),
          routing_key,
          payload,
          content_type: "application/json"
        )

        Logger.debug("[RabbitMQ] Routed message #{message.id} to #{destination}")
        :ok

      {:error, :not_connected} ->
        {:error, :not_connected}
    end
  end

  # ============================================================================
  # Helper Functions for Publishing (used by Broadway consumers)
  # ============================================================================

  @doc """
  Publishes a message to a node queue. Used by Broadway consumers for routing.
  """
  def publish_message(destination, message) do
    route(destination, message)
  end

  @doc """
  Publishes an event to the events exchange. Used by Broadway consumers.
  """
  def publish_event(event) do
    broadcast(event)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp node_queue_name(name), do: "node.#{name}"
  defp node_routing_key(name), do: "node.#{name}"

  defp encode_event(event) do
    :erlang.term_to_binary(event)
  end

  # Node tracking using Agent (started by Supervisor)
  defp track_node(name) do
    Agent.update(@node_tracker, &MapSet.put(&1, name))
  end

  defp untrack_node(name) do
    Agent.update(@node_tracker, &MapSet.delete(&1, name))
  end

  defp get_tracked_nodes do
    Agent.get(@node_tracker, &MapSet.to_list/1)
    |> Enum.sort()
  end
end
