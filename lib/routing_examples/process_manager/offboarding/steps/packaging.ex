defmodule RoutingExamples.ProcessManager.Offboarding.Steps.Packaging do
  @moduledoc """
  Packaging step that generates a ZIP file from gathered user data.

  Uses the intermediate results from the gathering step to create
  a comprehensive data export package.
  """

  @doc """
  Execute the packaging step.
  """
  def execute(instance) do
    # Get gathered data from intermediate results
    gathered_data = get_gathered_data(instance.intermediate_results)

    # Calculate total size (simulated)
    total_items = count_total_items(gathered_data)
    estimated_size = total_items * 1024 * 10  # ~10KB per item average

    # Simulate ZIP creation time based on data volume
    creation_time = 500 + div(total_items, 10) * 100
    Process.sleep(min(creation_time, 3000))

    # Generate fake ZIP path
    user_id = Map.get(instance.context, :id, "unknown")
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    zip_filename = "gdpr_export_#{user_id}_#{timestamp}.zip"
    zip_path = "/tmp/exports/#{zip_filename}"

    {:ok, %{
      zip_path: zip_path,
      zip_filename: zip_filename,
      size_bytes: estimated_size,
      item_count: total_items,
      created_at: DateTime.utc_now(),
      contents: summarize_contents(gathered_data)
    }}
  end

  defp get_gathered_data(intermediate_results) do
    intermediate_results
    |> Enum.filter(fn {key, _value} -> String.starts_with?(key, "gather:") end)
    |> Enum.into(%{})
  end

  defp count_total_items(gathered_data) do
    Enum.reduce(gathered_data, 0, fn {_key, value}, acc ->
      item_count = Map.get(value, :item_count, 1)
      acc + item_count
    end)
  end

  defp summarize_contents(gathered_data) do
    Enum.map(gathered_data, fn {key, value} ->
      source = String.replace_prefix(key, "gather:", "")
      %{
        source: source,
        item_count: Map.get(value, :item_count, 0),
        status: Map.get(value, :status, :unknown)
      }
    end)
  end
end
