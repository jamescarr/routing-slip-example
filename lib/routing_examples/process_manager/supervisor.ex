defmodule RoutingExamples.ProcessManager.Supervisor do
  @moduledoc """
  Supervisor for the Process Manager system.

  Manages:
  - Registry for worker name lookups
  - DynamicSupervisor for spawning workers dynamically
  - ProcessStore for instance persistence
  - MessageStore for message history
  """
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Registry for worker lookups by correlation_id or task_id
      {Registry, keys: :unique, name: RoutingExamples.ProcessManager.WorkerRegistry},

      # DynamicSupervisor for spawning workers on demand
      {DynamicSupervisor,
       name: RoutingExamples.ProcessManager.WorkerSupervisor,
       strategy: :one_for_one},

      # ETS-backed stores for persistence
      {RoutingExamples.ProcessManager.Store.ProcessStore, name: RoutingExamples.ProcessManager.Store.ProcessStore},
      {RoutingExamples.ProcessManager.Store.MessageStore, name: RoutingExamples.ProcessManager.Store.MessageStore}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
