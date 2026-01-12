defmodule RoutingExamples.ProcessManager.Offboarding.Steps.Purging do
  @moduledoc """
  Scatter/Gather step for deleting user data from all sources.

  Uses Task.async_stream for efficient parallel execution.
  Each data source is purged concurrently, ensuring complete
  data removal for GDPR compliance.
  """

  alias RoutingExamples.ProcessManager.Messenger

  @default_tasks [:profile, :documents, :folders, :activity_log, :preferences]

  @doc """
  Execute all purge tasks in parallel using Task.async_stream.
  """
  def execute(instance) do
    tasks = get_tasks(instance.context)
    correlation_id = instance.correlation_id

    # Broadcast that we're starting parallel purging
    Enum.each(tasks, fn task ->
      Messenger.broadcast({:task_started, correlation_id, "purge:#{task}"})
    end)

    # Execute all purge tasks in parallel
    results =
      tasks
      |> Task.async_stream(
        fn task ->
          result = purge_data(task, instance.context)

          # Broadcast individual task completion
          Messenger.broadcast({:task_completed, correlation_id, "purge:#{task}", %{
            deleted_count: result.deleted_count,
            completed_at: DateTime.utc_now()
          }})

          {task, result}
        end,
        timeout: :infinity,
        max_concurrency: System.schedulers_online()
      )
      |> Enum.reduce(%{}, fn {:ok, {task, data}}, acc ->
        Map.put(acc, "purge:#{task}", %{
          status: :completed,
          completed_at: DateTime.utc_now(),
          deleted_count: data.deleted_count
        })
      end)

    total_deleted =
      results
      |> Map.values()
      |> Enum.reduce(0, fn r, acc -> acc + Map.get(r, :deleted_count, 0) end)

    {:ok, Map.put(results, :total_deleted, total_deleted)}
  end

  defp get_tasks(context) do
    case Map.get(context, :data_sources) do
      sources when is_list(sources) -> sources
      _ -> @default_tasks
    end
  end

  defp purge_data(task, context) do
    # Random delay between 900-5000ms to demonstrate parallel scatter/gather
    delay = :rand.uniform(4100) + 900
    Process.sleep(delay)

    count =
      case task do
        :documents -> Map.get(context, :document_count, 10)
        :folders -> Map.get(context, :folder_count, 5)
        _ -> :rand.uniform(20)
      end

    %{
      source: task,
      deleted_count: count,
      deleted_at: DateTime.utc_now()
    }
  end
end
