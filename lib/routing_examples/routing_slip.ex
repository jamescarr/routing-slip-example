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

  This module delegates to the configured `Messenger` implementation,
  allowing the underlying transport to be swapped (PubSub, RabbitMQ, etc.).
  """

  alias RoutingExamples.RoutingSlip.Messenger

  # ============================================================================
  # Node Management (delegated to Messenger)
  # ============================================================================

  @doc """
  Creates and registers a new node with the given name.
  Returns {:ok, ref} on success, {:error, reason} on failure.
  """
  defdelegate create_node(name), to: Messenger

  @doc """
  Deletes a node by name.
  """
  defdelegate delete_node(name), to: Messenger

  @doc """
  Lists all registered node names.
  """
  defdelegate list_nodes(), to: Messenger

  @doc """
  Checks if a node with the given name exists.
  """
  defdelegate node_exists?(name), to: Messenger

  # ============================================================================
  # Message Sending
  # ============================================================================

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

    if Messenger.node_exists?(first_destination) do
      message_id = generate_message_id()

      message = %{
        id: message_id,
        payload: payload,
        routing_slip: destinations,
        visited: [],
        created_at: DateTime.utc_now()
      }

      # Broadcast that a new message journey is starting
      Messenger.broadcast({:message_started, message})

      # Route to first node
      case Messenger.route(first_destination, message) do
        :ok -> {:ok, message_id}
        {:error, _} = error -> error
      end
    else
      {:error, {:node_not_found, first_destination}}
    end
  end

  def send_message(_payload, []), do: {:error, :empty_routing_slip}

  defp generate_message_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
