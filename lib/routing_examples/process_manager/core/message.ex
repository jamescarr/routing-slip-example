defmodule RoutingExamples.ProcessManager.Core.Message do
  @moduledoc """
  Message struct for process manager communication.

  Every message carries a correlation_id that links it to its Process Instance,
  enabling proper routing and message history tracking.

  ## Message Types

  - `:process_started` - Process instance was created
  - `:step_started` - A step began execution
  - `:step_completed` - A step finished successfully
  - `:step_failed` - A step encountered an error
  - `:task_started` - A parallel task began (scatter)
  - `:task_completed` - A parallel task finished (gather)
  - `:process_completed` - The entire process finished
  - `:process_failed` - The process encountered a fatal error

  """

  @type message_type ::
          :process_started
          | :step_started
          | :step_completed
          | :step_failed
          | :task_started
          | :task_completed
          | :process_completed
          | :process_failed

  @type t :: %__MODULE__{
          id: String.t(),
          correlation_id: String.t(),
          type: message_type(),
          payload: map(),
          timestamp: DateTime.t()
        }

  @enforce_keys [:id, :correlation_id, :type]
  defstruct [
    :id,
    :correlation_id,
    :type,
    payload: %{},
    timestamp: nil
  ]

  @doc """
  Creates a new Message with the given attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: Map.get(attrs, :id, generate_id()),
      correlation_id: Map.fetch!(attrs, :correlation_id),
      type: Map.fetch!(attrs, :type),
      payload: Map.get(attrs, :payload, %{}),
      timestamp: Map.get(attrs, :timestamp, DateTime.utc_now())
    }
  end

  @doc """
  Creates a process_started message.
  """
  @spec process_started(String.t(), map()) :: t()
  def process_started(correlation_id, payload \\ %{}) do
    new(%{
      correlation_id: correlation_id,
      type: :process_started,
      payload: payload
    })
  end

  @doc """
  Creates a step_started message.
  """
  @spec step_started(String.t(), atom()) :: t()
  def step_started(correlation_id, step) do
    new(%{
      correlation_id: correlation_id,
      type: :step_started,
      payload: %{step: step}
    })
  end

  @doc """
  Creates a step_completed message.
  """
  @spec step_completed(String.t(), atom(), map()) :: t()
  def step_completed(correlation_id, step, result \\ %{}) do
    new(%{
      correlation_id: correlation_id,
      type: :step_completed,
      payload: %{step: step, result: result}
    })
  end

  @doc """
  Creates a task_completed message (for scatter/gather).
  """
  @spec task_completed(String.t(), String.t(), map()) :: t()
  def task_completed(correlation_id, task_id, result) do
    new(%{
      correlation_id: correlation_id,
      type: :task_completed,
      payload: %{task_id: task_id, result: result}
    })
  end

  defp generate_id do
    "msg_" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
  end
end
