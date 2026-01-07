defmodule RoutingExamples.ProcessManager.Offboarding.TestScenarios do
  @moduledoc """
  Predefined test scenarios demonstrating different offboarding paths.

  Each scenario represents a different user type with varying data and
  workflow requirements. Use these to demonstrate conditional routing
  and the scatter/gather pattern.
  """

  @scenarios [
    %{
      id: "scenario_1",
      name: "Basic User (No Shared Assets)",
      description: "Standard offboarding path, skips asset transfer step",
      user: %{
        id: "user_basic",
        email: "basic@example.com",
        name: "Basic User",
        has_shared_assets: false,
        data_sources: [:profile, :documents, :preferences],
        document_count: 15,
        folder_count: 3
      },
      expected_path: [:init, :gathering, :packaging, :uploading, :notifying, :purging, :completed]
    },
    %{
      id: "scenario_2",
      name: "Team Admin (Shared Assets)",
      description: "User with shared folders that need ownership transfer",
      user: %{
        id: "user_admin",
        email: "admin@example.com",
        name: "Team Administrator",
        has_shared_assets: true,
        successor_user_id: "user_new_admin",
        successor_email: "new_admin@example.com",
        shared_folders: ["team_docs", "projects"],
        data_sources: [:profile, :documents, :folders, :activity_log, :preferences],
        document_count: 150,
        folder_count: 12
      },
      expected_path: [:init, :gathering, :transferring, :packaging, :uploading, :notifying, :purging, :completed]
    },
    %{
      id: "scenario_3",
      name: "Large Data User",
      description: "User with extensive data, longer gathering phase",
      user: %{
        id: "user_large",
        email: "large@example.com",
        name: "Power User",
        has_shared_assets: false,
        document_count: 5000,
        folder_count: 200,
        data_sources: [:profile, :documents, :folders, :activity_log, :preferences, :backups]
      },
      expected_path: [:init, :gathering, :packaging, :uploading, :notifying, :purging, :completed],
      notes: "Demonstrates parallel gathering with many items - takes longer"
    },
    %{
      id: "scenario_4",
      name: "Enterprise User (Full Path)",
      description: "Enterprise user with all features: shared assets, large data",
      user: %{
        id: "user_enterprise",
        email: "enterprise@megacorp.com",
        name: "Enterprise Account",
        has_shared_assets: true,
        successor_user_id: "user_successor",
        successor_email: "successor@megacorp.com",
        shared_folders: ["department_shared", "cross_team"],
        custom_metadata: %{department: "Engineering", cost_center: "CC-123"},
        data_sources: [:profile, :documents, :folders, :activity_log, :preferences, :integrations, :api_keys],
        document_count: 2500,
        folder_count: 75
      },
      expected_path: [:init, :gathering, :transferring, :packaging, :uploading, :notifying, :purging, :completed]
    }
  ]

  @doc "List all available test scenarios."
  @spec list_scenarios() :: [map()]
  def list_scenarios, do: @scenarios

  @doc "Get a scenario by ID."
  @spec get_scenario(String.t()) :: map() | nil
  def get_scenario(id) when is_binary(id) do
    Enum.find(@scenarios, fn scenario -> scenario.id == id end)
  end

  @doc "Check if a scenario exists."
  @spec exists?(String.t()) :: boolean()
  def exists?(id) when is_binary(id) do
    Enum.any?(@scenarios, fn scenario -> scenario.id == id end)
  end

  @doc "Get scenarios that include the transfer step."
  @spec scenarios_with_transfer() :: [map()]
  def scenarios_with_transfer do
    Enum.filter(@scenarios, fn scenario ->
      :transferring in scenario.expected_path
    end)
  end

  @doc "Get scenario options for form select."
  @spec options_for_select() :: [{String.t(), String.t()}]
  def options_for_select do
    Enum.map(@scenarios, fn scenario ->
      {scenario.name, scenario.id}
    end)
  end
end
