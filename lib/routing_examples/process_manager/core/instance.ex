defmodule RoutingExamples.ProcessManager.Core.Instance do
  @moduledoc """
  Process Instance struct representing a running execution of a process definition.

  Each instance tracks:
  - Unique correlation ID for message routing
  - Current step in the workflow
  - Context data (user info, configuration)
  - Intermediate results from completed steps
  - Timestamps for auditing
  """

  @type t :: %__MODULE__{
          id: String.t(),
          correlation_id: String.t(),
          definition: atom(),
          current_step: atom(),
          context: map(),
          intermediate_results: map(),
          started_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @enforce_keys [:correlation_id, :definition]
  defstruct [
    :id,
    :correlation_id,
    :definition,
    current_step: :init,
    context: %{},
    intermediate_results: %{},
    started_at: nil,
    updated_at: nil
  ]

  @doc """
  Creates a new ProcessInstance with the given attributes.

  ## Examples

      iex> Instance.new(%{correlation_id: "test_123", definition: :offboarding})
      %Instance{correlation_id: "test_123", definition: :offboarding, ...}

  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    %__MODULE__{
      id: Map.get(attrs, :id, generate_id()),
      correlation_id: Map.fetch!(attrs, :correlation_id),
      definition: Map.fetch!(attrs, :definition),
      current_step: Map.get(attrs, :current_step, :init),
      context: Map.get(attrs, :context, %{}),
      intermediate_results: Map.get(attrs, :intermediate_results, %{}),
      started_at: Map.get(attrs, :started_at, now),
      updated_at: Map.get(attrs, :updated_at, now)
    }
  end

  @doc """
  Checks if the process instance has completed.
  """
  @spec completed?(t()) :: boolean()
  def completed?(%__MODULE__{current_step: :completed}), do: true
  def completed?(%__MODULE__{}), do: false

  @doc """
  Checks if the process instance has failed.
  """
  @spec failed?(t()) :: boolean()
  def failed?(%__MODULE__{current_step: :failed}), do: true
  def failed?(%__MODULE__{}), do: false

  @doc """
  Checks if the process instance is still active (not completed or failed).
  """
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{} = instance) do
    not completed?(instance) and not failed?(instance)
  end

  @doc """
  Gets an intermediate result by key.
  """
  @spec get_result(t(), String.t()) :: map() | nil
  def get_result(%__MODULE__{intermediate_results: results}, key) do
    Map.get(results, key)
  end

  @doc """
  Puts an intermediate result.
  """
  @spec put_result(t(), String.t(), map()) :: t()
  def put_result(%__MODULE__{} = instance, key, value) do
    updated_results = Map.put(instance.intermediate_results, key, value)
    %{instance | intermediate_results: updated_results, updated_at: DateTime.utc_now()}
  end

  @doc """
  Transitions the instance to a new step.
  """
  @spec transition_to(t(), atom()) :: t()
  def transition_to(%__MODULE__{} = instance, step) when is_atom(step) do
    %{instance | current_step: step, updated_at: DateTime.utc_now()}
  end

  defp generate_id do
    "inst_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
