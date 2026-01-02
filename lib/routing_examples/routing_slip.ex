defmodule RoutingExamples.RoutingSlip do
  @moduledoc """
  Context module for the Routing Slip pattern implementation.

  The Routing Slip pattern is an Enterprise Integration Pattern where a message
  carries its own itinerary, specifying the sequence of processing steps.

  Each processor:
  1. Receives the message
  2. Processes it
  3. Removes itself from the routing slip
  4. Forwards to the next destination
  """

  alias RoutingExamples.RoutingSlip.Node

  @doc """
  Creates and registers a new node with the given name.
  Returns {:ok, pid} on success, {:error, reason} on failure.
  """
  def create_node(name) when is_binary(name) and byte_size(name) > 0 do
    case DynamicSupervisor.start_child(
           RoutingExamples.RoutingSlip.NodeSupervisor,
           {Node, name}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:error, {:already_exists, pid}}
      error -> error
    end
  end

  @doc """
  Lists all registered node names.
  """
  def list_nodes do
    Registry.select(RoutingExamples.RoutingSlip.NodeRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.sort()
  end

  @doc """
  Checks if a node with the given name exists.
  """
  def node_exists?(name) do
    case Registry.lookup(RoutingExamples.RoutingSlip.NodeRegistry, name) do
      [{_pid, _value}] -> true
      [] -> false
    end
  end

  @doc """
  Gets stats for a specific node.
  """
  def get_node_stats(name) do
    if node_exists?(name) do
      Node.get_stats(name)
    else
      {:error, :not_found}
    end
  end

  @doc """
  Sends a message with a routing slip to the first destination.

  ## Parameters
  - payload: The message content (can be any term)
  - destinations: A list of node names representing the routing slip

  ## Returns
  - {:ok, message_id} on success
  - {:error, reason} on failure
  """
  def send_message(payload, destinations)
      when is_list(destinations) and length(destinations) > 0 do
    [first_destination | _rest] = destinations

    unless node_exists?(first_destination) do
      {:error, {:node_not_found, first_destination}}
    else
      message_id = generate_message_id()

      message = %{
        id: message_id,
        payload: payload,
        routing_slip: destinations,
        visited: [],
        created_at: DateTime.utc_now()
      }

      # Broadcast that a new message journey is starting
      Phoenix.PubSub.broadcast(
        RoutingExamples.PubSub,
        "routing_slip:updates",
        {:message_started, message}
      )

      # Send to first node
      Node.process_message(first_destination, message)

      {:ok, message_id}
    end
  end

  def send_message(_payload, []), do: {:error, :empty_routing_slip}

  defp generate_message_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
