defmodule RoutingExamples.ProcessManager.Messenger do
  @moduledoc """
  Behaviour for message transport in the Process Manager pattern.

  Reuses the same abstraction as Routing Slip, allowing:
  - `PubSub` - Phoenix.PubSub for real-time UI updates
  - Extensible for RabbitMQ or other transports

  ## Event Types

  - `{:process_started, instance}` - New process began
  - `{:step_started, correlation_id, step}` - Step execution began
  - `{:step_completed, correlation_id, step, result}` - Step finished
  - `{:task_started, correlation_id, task_id}` - Parallel task began
  - `{:task_completed, correlation_id, task_id, result}` - Parallel task finished
  - `{:process_completed, instance}` - Process finished successfully
  - `{:process_failed, correlation_id, error}` - Process encountered error

  """

  alias RoutingExamples.ProcessManager.Core.Instance

  @type event ::
          {:process_started, Instance.t()}
          | {:step_started, String.t(), atom()}
          | {:step_completed, String.t(), atom(), map()}
          | {:task_started, String.t(), String.t()}
          | {:task_completed, String.t(), String.t(), map()}
          | {:process_completed, Instance.t()}
          | {:process_failed, String.t(), term()}
          | {:intermediate_result_updated, String.t(), String.t(), map()}

  # ============================================================================
  # Callbacks
  # ============================================================================

  @callback broadcast(event()) :: :ok | {:error, term()}
  @callback subscribe() :: :ok | {:error, term()}
  @callback unsubscribe() :: :ok | {:error, term()}

  # ============================================================================
  # Convenience Functions
  # ============================================================================

  @doc """
  Returns the configured messenger implementation.
  """
  def impl do
    Application.get_env(
      :routing_examples,
      :process_manager_messenger,
      RoutingExamples.ProcessManager.Messenger.PubSub
    )
  end

  @doc "Broadcasts an event using the configured messenger."
  def broadcast(event), do: impl().broadcast(event)

  @doc "Subscribes the calling process using the configured messenger."
  def subscribe, do: impl().subscribe()

  @doc "Unsubscribes the calling process using the configured messenger."
  def unsubscribe, do: impl().unsubscribe()
end
