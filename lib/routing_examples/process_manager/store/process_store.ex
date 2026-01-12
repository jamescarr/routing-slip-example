defmodule RoutingExamples.ProcessManager.Store.ProcessStore do
  @moduledoc """
  GenServer-wrapped ETS store for Process Instances.

  Provides CRUD operations for process instances with:
  - Fast lookups by correlation_id
  - Listing of active processes
  - Proper OTP supervision lifecycle
  """
  use GenServer

  alias RoutingExamples.ProcessManager.Core.Instance

  @table_name :process_instances

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Saves a process instance to the store.
  """
  @spec save(Instance.t()) :: :ok
  def save(%Instance{} = instance) do
    :ets.insert(@table_name, {instance.correlation_id, instance})
    :ok
  end

  @doc """
  Gets a process instance by correlation_id.
  """
  @spec get(String.t()) :: {:ok, Instance.t()} | {:error, :not_found}
  def get(correlation_id) when is_binary(correlation_id) do
    case :ets.lookup(@table_name, correlation_id) do
      [{^correlation_id, instance}] -> {:ok, instance}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Deletes a process instance by correlation_id.
  """
  @spec delete(String.t()) :: :ok
  def delete(correlation_id) when is_binary(correlation_id) do
    :ets.delete(@table_name, correlation_id)
    :ok
  end

  @doc """
  Lists all process instances.
  """
  @spec list_all() :: [Instance.t()]
  def list_all do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {_id, instance} -> instance end)
  end

  @doc """
  Lists active (non-completed, non-failed) process instances.
  """
  @spec list_active() :: [Instance.t()]
  def list_active do
    list_all()
    |> Enum.filter(&Instance.active?/1)
  end

  @doc """
  Checks if a process instance exists.
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(correlation_id) when is_binary(correlation_id) do
    case :ets.lookup(@table_name, correlation_id) do
      [{^correlation_id, _}] -> true
      [] -> false
    end
  end

  @doc """
  Counts all process instances.
  """
  @spec count() :: non_neg_integer()
  def count do
    :ets.info(@table_name, :size)
  end

  @doc """
  Clears all process instances (useful for testing).
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
    table = :ets.new(@table_name, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{table: table}}
  end

  @impl true
  def terminate(_reason, _state) do
    # ETS table is automatically deleted when owner process terminates
    :ok
  end
end
