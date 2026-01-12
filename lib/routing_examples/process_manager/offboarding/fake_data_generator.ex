defmodule RoutingExamples.ProcessManager.Offboarding.FakeDataGenerator do
  @moduledoc """
  Generates fake user data for the offboarding demo.

  Simulates data gathering from various sources with realistic delays
  and data structures.
  """

  @doc """
  Generates fake data for a specific data source.
  """
  def generate(source, context) do
    # Simulate network/database latency
    delay = calculate_delay(source, context)
    Process.sleep(delay)

    # Generate appropriate fake data
    generate_data(source, context)
  end

  defp calculate_delay(source, context) do
    base_delay = 300

    # Add delay based on data volume
    volume_factor =
      case source do
        :documents -> Map.get(context, :document_count, 10) / 100
        :folders -> Map.get(context, :folder_count, 5) / 10
        _ -> 1
      end

    # Add some randomness
    random_factor = :rand.uniform(200)

    trunc(base_delay + base_delay * volume_factor + random_factor)
  end

  defp generate_data(:profile, context) do
    %{
      id: Map.get(context, :id, "user_unknown"),
      email: Map.get(context, :email, "unknown@example.com"),
      name: Map.get(context, :name, "Unknown User"),
      created_at: ~U[2023-01-15 10:30:00Z],
      last_login: DateTime.utc_now() |> DateTime.add(-3600, :second),
      settings: %{
        theme: "dark",
        notifications: true,
        language: "en"
      }
    }
  end

  defp generate_data(:documents, context) do
    count = min(Map.get(context, :document_count, 10), 50)

    for i <- 1..count do
      %{
        id: "doc_#{i}",
        name: Enum.random(document_names()) <> "_#{i}.#{Enum.random(["pdf", "docx", "xlsx", "txt"])}",
        size: :rand.uniform(1024 * 1024 * 10),
        created_at: random_past_date(),
        modified_at: random_past_date()
      }
    end
  end

  defp generate_data(:folders, context) do
    count = min(Map.get(context, :folder_count, 5), 20)

    for i <- 1..count do
      %{
        id: "folder_#{i}",
        name: Enum.random(folder_names()) <> "_#{i}",
        item_count: :rand.uniform(50),
        shared: i <= 2 and Map.get(context, :has_shared_assets, false),
        created_at: random_past_date()
      }
    end
  end

  defp generate_data(:activity_log, _context) do
    activities = [
      "Logged in",
      "Updated profile",
      "Uploaded document",
      "Shared folder",
      "Downloaded file",
      "Changed settings",
      "Invited team member"
    ]

    for i <- 1..25 do
      %{
        id: "activity_#{i}",
        action: Enum.random(activities),
        timestamp: random_past_date(),
        ip_address: "192.168.1.#{:rand.uniform(255)}",
        user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
      }
    end
  end

  defp generate_data(:preferences, _context) do
    %{
      email_notifications: %{
        marketing: false,
        product_updates: true,
        security_alerts: true
      },
      privacy: %{
        profile_visibility: "private",
        search_indexing: false
      },
      integrations: %{
        google_drive: true,
        dropbox: false,
        slack: true
      }
    }
  end

  defp generate_data(:backups, context) do
    count = min(Map.get(context, :document_count, 10) / 10, 10) |> trunc() |> max(1)

    for i <- 1..count do
      %{
        id: "backup_#{i}",
        created_at: random_past_date(),
        size: :rand.uniform(1024 * 1024 * 100),
        status: "completed"
      }
    end
  end

  defp generate_data(:integrations, _context) do
    [
      %{id: "int_1", name: "Google Workspace", connected_at: random_past_date()},
      %{id: "int_2", name: "Slack", connected_at: random_past_date()},
      %{id: "int_3", name: "Jira", connected_at: random_past_date()}
    ]
  end

  defp generate_data(:api_keys, _context) do
    [
      %{id: "key_1", name: "Production API Key", prefix: "pk_live_", created_at: random_past_date()},
      %{id: "key_2", name: "Test API Key", prefix: "pk_test_", created_at: random_past_date()}
    ]
  end

  defp generate_data(source, _context) do
    %{source: source, data: "No data available"}
  end

  defp document_names do
    [
      "Report",
      "Invoice",
      "Contract",
      "Presentation",
      "Spreadsheet",
      "Notes",
      "Meeting_Minutes",
      "Project_Plan",
      "Budget",
      "Proposal"
    ]
  end

  defp folder_names do
    [
      "Projects",
      "Archive",
      "Shared",
      "Personal",
      "Work",
      "Templates",
      "Resources",
      "Backups",
      "Documents",
      "Reports"
    ]
  end

  defp random_past_date do
    days_ago = :rand.uniform(365)
    DateTime.utc_now() |> DateTime.add(-days_ago * 24 * 3600, :second)
  end
end
