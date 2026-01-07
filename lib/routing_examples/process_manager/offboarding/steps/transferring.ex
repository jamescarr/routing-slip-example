defmodule RoutingExamples.ProcessManager.Offboarding.Steps.Transferring do
  @moduledoc """
  Asset transfer step for users with shared resources.

  Transfers ownership of shared folders and documents to a designated
  successor user. This step is only executed when the user context
  indicates `has_shared_assets: true`.
  """

  @doc """
  Execute the asset transfer step.
  """
  def execute(instance) do
    context = instance.context

    shared_folders = Map.get(context, :shared_folders, [])
    successor_id = Map.get(context, :successor_user_id)
    successor_email = Map.get(context, :successor_email, "unknown@example.com")

    # Simulate transfer process
    transferred =
      Enum.map(shared_folders, fn folder ->
        # Simulate API call delay
        Process.sleep(200 + :rand.uniform(300))

        %{
          folder: folder,
          transferred_to: successor_id,
          transferred_at: DateTime.utc_now(),
          status: :completed
        }
      end)

    {:ok, %{
      transferred_folders: transferred,
      successor_user_id: successor_id,
      successor_email: successor_email,
      total_transferred: length(transferred)
    }}
  end
end
