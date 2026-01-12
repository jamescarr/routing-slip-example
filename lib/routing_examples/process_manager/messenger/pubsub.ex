defmodule RoutingExamples.ProcessManager.Messenger.PubSub do
  @moduledoc """
  Phoenix.PubSub implementation of the Messenger behaviour.

  This is the default messenger for in-process communication,
  perfect for single-node deployments and development.

  Uses Phoenix.PubSub for broadcasting events to subscribers
  (typically LiveView processes for real-time UI updates).
  """

  @behaviour RoutingExamples.ProcessManager.Messenger

  @topic "process_manager:updates"

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
end
