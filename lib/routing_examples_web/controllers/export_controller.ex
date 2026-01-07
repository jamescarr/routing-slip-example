defmodule RoutingExamplesWeb.ExportController do
  @moduledoc """
  Controller for handling data export downloads.

  Proxies downloads from S3 and tracks when files are accessed,
  sending messages to the Process Manager for audit trail.
  """
  use RoutingExamplesWeb, :controller
  require Logger

  alias RoutingExamples.ProcessManager
  alias RoutingExamples.ProcessManager.{Messenger, S3Client}
  alias RoutingExamples.ProcessManager.Store.ProcessStore

  @doc """
  Download a data export by correlation_id.

  This endpoint:
  1. Validates the process exists and has completed uploading
  2. Fetches the file from S3
  3. Streams it to the client with proper headers
  4. Records the download event
  """
  def download(conn, %{"correlation_id" => correlation_id}) do
    case ProcessStore.get(correlation_id) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Export not found", correlation_id: correlation_id})

      {:ok, instance} ->
        handle_download(conn, instance)
    end
  end

  defp handle_download(conn, instance) do
    case get_s3_key(instance) do
      {:ok, s3_key, filename} ->
        download_and_stream(conn, instance, s3_key, filename)

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason, correlation_id: instance.correlation_id})
    end
  end

  defp get_s3_key(instance) do
    case Map.get(instance.intermediate_results, "uploading") do
      %{data: %{key: key}} when is_binary(key) ->
        filename = Path.basename(key)
        {:ok, key, filename}

      _ ->
        {:error, "Export not yet available. Process may still be running."}
    end
  end

  defp download_and_stream(conn, instance, s3_key, filename) do
    Logger.info("Processing download request for #{s3_key} (process: #{instance.correlation_id})")

    case S3Client.download(s3_key) do
      {:ok, content} ->
        # Record the download event
        record_download(instance)

        # Stream the file to the client
        conn
        |> put_resp_content_type("application/zip")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        |> put_resp_header("content-length", "#{byte_size(content)}")
        |> send_resp(200, content)

      {:error, reason} ->
        Logger.error("Failed to download from S3: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to retrieve export", details: inspect(reason)})
    end
  end

  defp record_download(instance) do
    download_event = %{
      downloaded_at: DateTime.utc_now(),
      downloaded_by: "user",  # In a real app, this would be the authenticated user
      correlation_id: instance.correlation_id
    }

    # Update the process with download info
    ProcessManager.record_download(instance.correlation_id, download_event)

    # Broadcast the download event
    Messenger.broadcast({:export_downloaded, instance.correlation_id, download_event})

    Logger.info("Recorded download for process #{instance.correlation_id}")
  end
end
