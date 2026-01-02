defmodule RoutingExamples.RoutingSlip.Supervisor do
  @moduledoc """
  Supervisor for the Routing Slip system.

  Manages:
  - Registry for node name lookups
  - DynamicSupervisor for spawning nodes dynamically
  """
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Registry, keys: :unique, name: RoutingExamples.RoutingSlip.NodeRegistry},
      {DynamicSupervisor,
       name: RoutingExamples.RoutingSlip.NodeSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
