defmodule RoutingExamples.RoutingSlip.Node do
  @moduledoc """
  A GenServer that represents a node in the routing slip pattern.

  Each node:
  - Receives messages with a routing slip
  - Adds itself to the "visited" list
  - Pops itself from the routing slip
  - Forwards to the next destination (if any)
  - Broadcasts updates via PubSub for real-time UI updates
  """
  use GenServer

  alias Phoenix.PubSub

  @pubsub RoutingExamples.PubSub
  @topic "routing_slip:updates"

  # Client API

  def start_link(name) when is_binary(name) do
    GenServer.start_link(__MODULE__, name, name: via_tuple(name))
  end

  def process_message(node_name, message) do
    GenServer.cast(via_tuple(node_name), {:process_message, message})
  end

  def get_stats(node_name) do
    GenServer.call(via_tuple(node_name), :get_stats)
  end

  def via_tuple(name) do
    {:via, Registry, {RoutingExamples.RoutingSlip.NodeRegistry, name}}
  end

  # Server callbacks

  @impl true
  def init(name) do
    state = %{
      name: name,
      messages_processed: 0,
      created_at: DateTime.utc_now()
    }

    # Broadcast that this node was created
    PubSub.broadcast(@pubsub, @topic, {:node_created, name})

    {:ok, state}
  end

  @impl true
  def handle_cast({:process_message, message}, state) do
    %{routing_slip: routing_slip, visited: visited, payload: payload, id: message_id} = message

    # Add ourselves to visited with the current step number
    step_number = length(visited) + 1
    new_visited = visited ++ [{state.name, step_number, DateTime.utc_now()}]

    # Pop ourselves from the routing slip
    [_current | remaining_slip] = routing_slip

    updated_message = %{
      id: message_id,
      payload: payload,
      routing_slip: remaining_slip,
      visited: new_visited
    }

    new_state = %{state | messages_processed: state.messages_processed + 1}

    # Broadcast that we processed this message
    PubSub.broadcast(@pubsub, @topic, {:message_processed, state.name, updated_message})

    # Forward to next destination if there is one
    case remaining_slip do
      [next_destination | _rest] ->
        # Small delay for visualization effect
        Process.send_after(self(), {:forward_message, next_destination, updated_message}, 300)

      [] ->
        # Message completed its journey
        PubSub.broadcast(@pubsub, @topic, {:message_completed, updated_message})
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:forward_message, next_destination, message}, state) do
    process_message(next_destination, message)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end
end
