defmodule RoutingExamples.ProcessManager do
  @moduledoc """
  Context module for the Process Manager pattern implementation.

  The Process Manager pattern is an Enterprise Integration Pattern where a
  central coordinator orchestrates complex, long-running workflows. Unlike
  the Routing Slip (choreography), the Process Manager (orchestration)
  maintains state externally, enabling:

  - Full visibility into workflow progress
  - Human intervention capabilities
  - Complex branching and conditional routing
  - Scatter/gather parallel execution
  - Intermediate results storage

  This implementation demonstrates GDPR user offboarding with:
  - Parallel data gathering from multiple sources
  - Conditional asset transfer (for users with shared assets)
  - ZIP generation and S3 upload
  - Full message history for audit trail

  ## Usage

      # Start an offboarding process
      {:ok, instance} = ProcessManager.start_offboarding("scenario_1")

      # Check current state
      instance = ProcessManager.get_instance(correlation_id)

      # List active processes
      processes = ProcessManager.list_active_processes()

  """

  alias RoutingExamples.ProcessManager.{
    Core.Instance,
    Store.ProcessStore,
    Store.MessageStore,
    Offboarding.Definition,
    Offboarding.TestScenarios,
    Messenger
  }

  # ============================================================================
  # Process Lifecycle
  # ============================================================================

  @doc """
  Starts a new offboarding process for the given scenario.

  Returns `{:ok, instance}` on success, `{:error, reason}` on failure.
  """
  def start_offboarding(scenario_id) when is_binary(scenario_id) do
    case TestScenarios.get_scenario(scenario_id) do
      nil ->
        {:error, :scenario_not_found}

      scenario ->
        correlation_id = generate_correlation_id()

        instance = Instance.new(%{
          correlation_id: correlation_id,
          definition: :offboarding,
          context: scenario.user,
          current_step: :init
        })

        # Store the instance
        :ok = ProcessStore.save(instance)

        # Record the start message
        message = %{
          id: generate_message_id(),
          correlation_id: correlation_id,
          type: :process_started,
          payload: %{scenario_id: scenario_id},
          timestamp: DateTime.utc_now()
        }
        :ok = MessageStore.store(message)

        # Broadcast the start event
        Messenger.broadcast({:process_started, instance})

        # Begin execution
        execute_step(instance)

        {:ok, instance}
    end
  end

  @doc """
  Gets a process instance by correlation ID.
  """
  def get_instance(correlation_id) do
    ProcessStore.get(correlation_id)
  end

  @doc """
  Refreshes an instance from the store (for LiveView updates).
  """
  def refresh_instance(%Instance{correlation_id: correlation_id}) do
    case ProcessStore.get(correlation_id) do
      {:ok, instance} -> instance
      {:error, _} -> nil
    end
  end

  def refresh_instance(nil), do: nil

  @doc """
  Lists all active (non-completed) process instances.
  """
  def list_active_processes do
    ProcessStore.list_active()
  end

  @doc """
  Gets the process definition for a given type.
  """
  def get_definition(:offboarding), do: Definition.get()
  def get_definition(_), do: nil

  @doc """
  Gets the message history for a process.
  """
  def get_message_history(correlation_id) do
    MessageStore.get_history(correlation_id)
  end

  # ============================================================================
  # Step Execution
  # ============================================================================

  @doc """
  Executes the current step of a process instance.
  """
  def execute_step(%Instance{current_step: step, correlation_id: correlation_id} = instance) do
    # Broadcast step started
    Messenger.broadcast({:step_started, correlation_id, step})

    # Record the step start
    message = %{
      id: generate_message_id(),
      correlation_id: correlation_id,
      type: :step_started,
      payload: %{step: step},
      timestamp: DateTime.utc_now()
    }
    MessageStore.store(message)

    # Execute the step (async via workers)
    spawn_link(fn ->
      result = execute_step_impl(step, instance)
      handle_step_result(instance, step, result)
    end)

    :ok
  end

  defp execute_step_impl(:init, _instance) do
    # Initialization step - just transition immediately
    Process.sleep(100)  # Small delay for visualization
    {:ok, %{initialized: true}}
  end

  defp execute_step_impl(:gathering, instance) do
    # Delegate to the Gathering step module
    alias RoutingExamples.ProcessManager.Offboarding.Steps.Gathering
    Gathering.execute(instance)
  end

  defp execute_step_impl(:transferring, instance) do
    alias RoutingExamples.ProcessManager.Offboarding.Steps.Transferring
    Transferring.execute(instance)
  end

  defp execute_step_impl(:packaging, instance) do
    alias RoutingExamples.ProcessManager.Offboarding.Steps.Packaging
    Packaging.execute(instance)
  end

  defp execute_step_impl(:uploading, instance) do
    alias RoutingExamples.ProcessManager.Offboarding.Steps.Uploading
    Uploading.execute(instance)
  end

  defp execute_step_impl(:notifying, instance) do
    alias RoutingExamples.ProcessManager.Offboarding.Steps.Notifying
    Notifying.execute(instance)
  end

  defp execute_step_impl(:purging, instance) do
    alias RoutingExamples.ProcessManager.Offboarding.Steps.Purging
    Purging.execute(instance)
  end

  defp execute_step_impl(:completed, _instance) do
    {:ok, %{completed: true}}
  end

  defp execute_step_impl(step, _instance) do
    {:error, {:unknown_step, step}}
  end

  # ============================================================================
  # Step Result Handling
  # ============================================================================

  @doc false
  def handle_step_result(instance, step, {:ok, result}) do
    correlation_id = instance.correlation_id

    # Update intermediate results
    updated_results = Map.put(
      instance.intermediate_results,
      Atom.to_string(step),
      %{status: :completed, completed_at: DateTime.utc_now(), data: result}
    )

    # Determine next step
    next_step = determine_next_step(step, instance.context)

    # Update instance
    updated_instance = %{instance |
      current_step: next_step,
      intermediate_results: updated_results,
      updated_at: DateTime.utc_now()
    }

    ProcessStore.save(updated_instance)

    # Record completion message
    message = %{
      id: generate_message_id(),
      correlation_id: correlation_id,
      type: :step_completed,
      payload: %{step: step, result: result},
      timestamp: DateTime.utc_now()
    }
    MessageStore.store(message)

    # Broadcast completion
    Messenger.broadcast({:step_completed, correlation_id, step, result})

    # Continue to next step if not completed
    if next_step != :completed do
      execute_step(updated_instance)
    else
      Messenger.broadcast({:process_completed, updated_instance})
    end
  end

  def handle_step_result(instance, step, {:error, reason}) do
    correlation_id = instance.correlation_id

    # Update instance with error
    updated_instance = %{instance |
      current_step: :failed,
      updated_at: DateTime.utc_now()
    }

    ProcessStore.save(updated_instance)

    # Record error message
    message = %{
      id: generate_message_id(),
      correlation_id: correlation_id,
      type: :step_failed,
      payload: %{step: step, error: reason},
      timestamp: DateTime.utc_now()
    }
    MessageStore.store(message)

    # Broadcast failure
    Messenger.broadcast({:process_failed, correlation_id, reason})
  end

  # ============================================================================
  # Routing Logic
  # ============================================================================

  defp determine_next_step(:init, _context), do: :gathering

  defp determine_next_step(:gathering, context) do
    if Map.get(context, :has_shared_assets, false) do
      :transferring
    else
      :packaging
    end
  end

  defp determine_next_step(:transferring, _context), do: :packaging
  defp determine_next_step(:packaging, _context), do: :uploading
  defp determine_next_step(:uploading, _context), do: :notifying
  defp determine_next_step(:notifying, _context), do: :purging
  defp determine_next_step(:purging, _context), do: :completed
  defp determine_next_step(:completed, _context), do: :completed

  # ============================================================================
  # Download Tracking
  # ============================================================================

  @doc """
  Records that a data export was downloaded.
  Updates the process instance with download metadata.
  """
  def record_download(correlation_id, download_event) do
    case ProcessStore.get(correlation_id) do
      {:error, :not_found} ->
        {:error, :process_not_found}

      {:ok, instance} ->
        # Add download info to intermediate results
        upload_result = Map.get(instance.intermediate_results, "uploading", %{})
        updated_upload = Map.put(upload_result, :download_info, download_event)

        updated_results = Map.put(
          instance.intermediate_results,
          "uploading",
          updated_upload
        )

        updated_instance = %{instance |
          intermediate_results: updated_results,
          updated_at: DateTime.utc_now()
        }

        ProcessStore.save(updated_instance)

        # Record the download message
        message = %{
          id: generate_message_id(),
          correlation_id: correlation_id,
          type: :export_downloaded,
          payload: download_event,
          timestamp: DateTime.utc_now()
        }
        MessageStore.store(message)

        {:ok, updated_instance}
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp generate_correlation_id do
    "offboard_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp generate_message_id do
    "msg_" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
  end
end
