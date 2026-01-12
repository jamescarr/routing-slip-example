defmodule RoutingExamples.ProcessManager.Store.MessageStore do
  @moduledoc """
  GenServer-wrapped ETS store for Message History.

  Stores all messages by correlation_id for:
  - Debugging workflow execution
  - Compliance auditing (GDPR)
  - Replaying failed processes

  Uses a :bag table type to allow multiple messages per correlation_id.
  """
  use GenServer

  @table_name :process_messages

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Stores a message in the history.
  """
  @spec store(map()) :: :ok
  def store(message) when is_map(message) do
    correlation_id = Map.fetch!(message, :correlation_id)
    :ets.insert(@table_name, {correlation_id, message})
    :ok
  end

  @doc """
  Gets full message history for a correlation_id, sorted by timestamp.
  """
  @spec get_history(String.t()) :: [map()]
  def get_history(correlation_id) when is_binary(correlation_id) do
    @table_name
    |> :ets.lookup(correlation_id)
    |> Enum.map(fn {_id, msg} -> msg end)
    |> Enum.sort_by(fn msg -> msg.timestamp end, DateTime)
  end

  @doc """
  Gets messages of a specific type for a correlation_id.
  """
  @spec get_by_type(String.t(), atom()) :: [map()]
  def get_by_type(correlation_id, type) when is_binary(correlation_id) and is_atom(type) do
    correlation_id
    |> get_history()
    |> Enum.filter(fn msg -> msg.type == type end)
  end

  @doc """
  Checks if any messages exist for a correlation_id.
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(correlation_id) when is_binary(correlation_id) do
    case :ets.lookup(@table_name, correlation_id) do
      [] -> false
      _ -> true
    end
  end

  @doc """
  Counts messages for a correlation_id.
  """
  @spec count(String.t()) :: non_neg_integer()
  def count(correlation_id) when is_binary(correlation_id) do
    @table_name
    |> :ets.lookup(correlation_id)
    |> length()
  end

  @doc """
  Gets the most recent message for a correlation_id.
  """
  @spec get_latest(String.t()) :: map() | nil
  def get_latest(correlation_id) when is_binary(correlation_id) do
    correlation_id
    |> get_history()
    |> List.last()
  end

  @doc """
  Clears all messages (useful for testing).
  """
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Create ETS table owned by this GenServer
    # :bag allows multiple values per key (multiple messages per correlation_id)
    table = :ets.new(@table_name, [
      :bag,
      :named_table,
      :public,
      read_concurrency: true
    ])

    {:ok, %{table: table}}
  end

  @impl true
  def terminate(_reason, _state) do
    # ETS table is automatically deleted when owner process terminates
    :ok
  end
end
