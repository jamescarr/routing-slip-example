defmodule RoutingExamples.ProcessManager.Offboarding.Steps.Gathering do
  @moduledoc """
  Scatter/Gather step for collecting user data from multiple sources.

  Uses Task.async_stream for efficient parallel execution with back-pressure.
  Each data source is gathered concurrently, and results are aggregated
  into the intermediate_results map.
  """

  alias RoutingExamples.ProcessManager.Offboarding.FakeDataGenerator
  alias RoutingExamples.ProcessManager.Messenger

  @default_tasks [:profile, :documents, :folders, :activity_log, :preferences]

  @doc """
  Execute all gather tasks in parallel using Task.async_stream.
  Returns {:ok, results} on success.
  """
  def execute(instance) do
    tasks = get_tasks(instance.context)
    correlation_id = instance.correlation_id

    # Broadcast that we're starting parallel gathering
    Enum.each(tasks, fn task ->
      Messenger.broadcast({:task_started, correlation_id, "gather:#{task}"})
    end)

    # Execute all tasks in parallel with Task.async_stream
    # Always use timeout: :infinity for potentially long-running operations
    results =
      tasks
      |> Task.async_stream(
        fn task ->
          # Random delay between 900-5000ms to demonstrate parallel scatter/gather
          delay = :rand.uniform(4100) + 900
          Process.sleep(delay)

          result = FakeDataGenerator.generate(task, instance.context)

          # Broadcast individual task completion
          Messenger.broadcast({:task_completed, correlation_id, "gather:#{task}", %{
            item_count: count_items(result),
            completed_at: DateTime.utc_now()
          }})

          {task, result}
        end,
        timeout: :infinity,
        max_concurrency: System.schedulers_online()
      )
      |> Enum.reduce(%{}, fn {:ok, {task, data}}, acc ->
        Map.put(acc, "gather:#{task}", %{
          status: :completed,
          completed_at: DateTime.utc_now(),
          data: data,
          item_count: count_items(data)
        })
      end)

    {:ok, results}
  end

  defp get_tasks(context) do
    case Map.get(context, :data_sources) do
      sources when is_list(sources) -> sources
      _ -> @default_tasks
    end
  end

  defp count_items(data) when is_list(data), do: length(data)
  defp count_items(data) when is_map(data), do: map_size(data)
  defp count_items(_), do: 1
end
