defmodule RoutingExamples.RoutingSlip.Messenger.RabbitMQ.NodeConsumer do
  @moduledoc """
  Broadway consumer for processing routing slip messages at a specific node.

  Each node gets its own Broadway pipeline that:
  1. Consumes messages from its dedicated queue (`node.{name}`)
  2. Processes the message (adds to visited, pops from routing slip)
  3. Broadcasts progress events
  4. Routes to the next node or marks as complete

  ## Starting Dynamically

  Consumers are started dynamically via `DynamicSupervisor`:

      DynamicSupervisor.start_child(
        RabbitMQ.ConsumerSupervisor,
        {NodeConsumer, node_name: "validator", connection: conn_opts}
      )

  ## Stopping

      NodeConsumer.stop("validator")

  See: https://hexdocs.pm/broadway/Broadway.html
  See: https://hexdocs.pm/broadway_rabbitmq/BroadwayRabbitMQ.Producer.html
  """
  use Broadway

  alias Broadway.Message
  alias RoutingExamples.RoutingSlip.Messenger.RabbitMQ
  alias RoutingExamples.RoutingSlip.Messenger.RabbitMQ.Connection

  require Logger

  @forward_delay_ms 500

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Returns the child spec for starting this consumer under a supervisor.
  """
  def child_spec(opts) do
    node_name = Keyword.fetch!(opts, :node_name)

    %{
      id: {__MODULE__, node_name},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      type: :supervisor
    }
  end

  @doc """
  Starts a Broadway consumer for the given node.
  """
  def start_link(opts) do
    node_name = Keyword.fetch!(opts, :node_name)

    # Broadway requires atom names, so we generate one dynamically
    broadway_name = :"#{__MODULE__}.#{node_name}"

    Broadway.start_link(__MODULE__,
      name: broadway_name,
      producer: [
        module: {
          BroadwayRabbitMQ.Producer,
          queue: "node.#{node_name}",
          connection: Connection.connection_opts(),
          on_failure: :reject,
          qos: [prefetch_count: 10]
        }
      ],
      processors: [
        default: [concurrency: 2]
      ],
      context: %{node_name: node_name, broadway_name: broadway_name}
    )
  end

  @doc """
  Stops the Broadway consumer for the given node.
  """
  def stop(node_name) do
    broadway_name = broadway_name(node_name)

    case Process.whereis(broadway_name) do
      nil ->
        {:error, :not_found}

      pid when is_pid(pid) ->
        Broadway.stop(broadway_name)
        :ok
    end
  end

  @doc """
  Returns the Broadway process name for a given node.
  """
  def broadway_name(node_name) do
    :"#{__MODULE__}.#{node_name}"
  end

  @doc """
  Checks if a consumer is running for the given node.
  """
  def running?(node_name) do
    broadway_name(node_name)
    |> Process.whereis()
    |> is_pid()
  end

  # ============================================================================
  # Broadway Callbacks
  # ============================================================================

  @impl true
  def handle_message(_, %Message{data: data} = message, context) do
    %{node_name: node_name} = context

    case Jason.decode(data) do
      {:ok, slip_message} ->
        process_slip_message(slip_message, node_name)
        message

      {:error, reason} ->
        Logger.error("[NodeConsumer:#{node_name}] Failed to decode message: #{inspect(reason)}")
        Message.failed(message, reason)
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp process_slip_message(message, node_name) do
    # Extract fields (message comes as map with string keys from JSON)
    routing_slip = message["routing_slip"]
    visited = message["visited"] || []
    payload = message["payload"]
    message_id = message["id"]

    # Add ourselves to visited with step number
    step_number = length(visited) + 1
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    new_visited = visited ++ [%{"node" => node_name, "step" => step_number, "timestamp" => timestamp}]

    # Pop ourselves from the routing slip
    [_current | remaining_slip] = routing_slip

    updated_message = %{
      "id" => message_id,
      "payload" => payload,
      "routing_slip" => remaining_slip,
      "visited" => new_visited
    }

    Logger.debug("[NodeConsumer:#{node_name}] Processed message #{message_id}, step #{step_number}")

    # Broadcast progress event
    broadcast_processed(node_name, updated_message)

    # Route to next or complete (with delay for visualization)
    Process.sleep(@forward_delay_ms)

    case remaining_slip do
      [next_destination | _rest] ->
        route_to_next(next_destination, updated_message)

      [] ->
        broadcast_completed(updated_message)
    end
  end

  defp broadcast_processed(node_name, message) do
    # Convert to internal format for broadcast
    event = {:message_processed, node_name, to_internal_message(message)}
    RabbitMQ.publish_event(event)
  end

  defp broadcast_completed(message) do
    event = {:message_completed, to_internal_message(message)}
    RabbitMQ.publish_event(event)
  end

  defp route_to_next(destination, message) do
    # Publish JSON to the next node's queue via exchange
    case Connection.get_channel() do
      {:ok, channel} ->
        routing_key = "node.#{destination}"
        payload = Jason.encode!(message)

        AMQP.Basic.publish(
          channel,
          Connection.messages_exchange(),
          routing_key,
          payload,
          content_type: "application/json"
        )

        Logger.debug("[NodeConsumer] Routed to #{destination}")

      {:error, :not_connected} ->
        Logger.error("[NodeConsumer] Cannot route - not connected")
    end
  end

  # Convert JSON message format to internal format (with atom keys and tuples for visited)
  defp to_internal_message(message) do
    visited =
      Enum.map(message["visited"], fn v ->
        {v["node"], v["step"], parse_timestamp(v["timestamp"])}
      end)

    %{
      id: message["id"],
      payload: message["payload"],
      routing_slip: message["routing_slip"],
      visited: visited
    }
  end

  defp parse_timestamp(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(_), do: DateTime.utc_now()
end
