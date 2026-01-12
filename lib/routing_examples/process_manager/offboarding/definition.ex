defmodule RoutingExamples.ProcessManager.Offboarding.Definition do
  @moduledoc """
  Process Definition for GDPR User Offboarding.

  This is the static workflow template defining:
  - Available steps in the process
  - Valid transitions between steps
  - Step metadata for UI rendering

  ## Workflow Steps

  1. **init** - Initialize the offboarding process
  2. **gathering** - Scatter/gather: collect user data from multiple sources
  3. **transferring** - (Optional) Transfer shared assets to successor
  4. **packaging** - Generate ZIP file from gathered data
  5. **uploading** - Upload to S3 and generate signed URL
  6. **notifying** - Notify user that export is ready
  7. **purging** - Scatter/gather: delete user data from all sources
  8. **completed** - Process finished

  """

  @steps [
    %{
      id: :init,
      name: "Initialize",
      description: "Set up the offboarding process",
      icon: "hero-play",
      color: "primary"
    },
    %{
      id: :gathering,
      name: "Gathering Data",
      description: "Collect user data from all sources (parallel)",
      icon: "hero-arrow-down-tray",
      color: "info",
      parallel: true,
      tasks: [:profile, :documents, :folders, :activity_log, :preferences]
    },
    %{
      id: :transferring,
      name: "Transferring Assets",
      description: "Transfer shared assets to successor",
      icon: "hero-arrow-right-on-rectangle",
      color: "warning",
      optional: true
    },
    %{
      id: :packaging,
      name: "Packaging",
      description: "Generate ZIP file with all user data",
      icon: "hero-archive-box",
      color: "secondary"
    },
    %{
      id: :uploading,
      name: "Uploading",
      description: "Upload to S3 and create signed URL",
      icon: "hero-cloud-arrow-up",
      color: "accent"
    },
    %{
      id: :notifying,
      name: "Notifying",
      description: "Send download link to user",
      icon: "hero-envelope",
      color: "info"
    },
    %{
      id: :purging,
      name: "Purging Data",
      description: "Delete user data from all sources (parallel)",
      icon: "hero-trash",
      color: "error",
      parallel: true,
      tasks: [:profile, :documents, :folders, :activity_log, :preferences]
    },
    %{
      id: :completed,
      name: "Completed",
      description: "Offboarding process finished",
      icon: "hero-check-circle",
      color: "success"
    }
  ]

  @transitions %{
    init: [:gathering],
    gathering: [:transferring, :packaging],
    transferring: [:packaging],
    packaging: [:uploading],
    uploading: [:notifying],
    notifying: [:purging],
    purging: [:completed],
    completed: []
  }

  @doc """
  Gets the complete process definition.
  """
  def get do
    %{
      id: :offboarding,
      name: "GDPR User Offboarding",
      description: "Complete user data export and deletion for GDPR compliance",
      steps: @steps,
      transitions: @transitions
    }
  end

  @doc """
  Gets all steps in order.
  """
  def steps, do: @steps

  @doc """
  Gets a step by ID.
  """
  def get_step(step_id) do
    Enum.find(@steps, fn step -> step.id == step_id end)
  end

  @doc """
  Gets valid next steps from a given step.
  """
  def valid_transitions(step_id) do
    Map.get(@transitions, step_id, [])
  end

  @doc """
  Checks if a transition is valid.
  """
  def valid_transition?(from, to) do
    to in valid_transitions(from)
  end

  @doc """
  Gets the linear step sequence (for basic UI rendering).
  """
  def step_sequence do
    [:init, :gathering, :transferring, :packaging, :uploading, :notifying, :purging, :completed]
  end

  @doc """
  Checks if a step is a parallel (scatter/gather) step.
  """
  def parallel_step?(step_id) do
    case get_step(step_id) do
      %{parallel: true} -> true
      _ -> false
    end
  end

  @doc """
  Gets the parallel tasks for a scatter/gather step.
  """
  def parallel_tasks(step_id) do
    case get_step(step_id) do
      %{tasks: tasks} -> tasks
      _ -> []
    end
  end
end
