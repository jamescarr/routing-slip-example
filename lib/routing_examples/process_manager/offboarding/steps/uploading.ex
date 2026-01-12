defmodule RoutingExamples.ProcessManager.Offboarding.Steps.Uploading do
  @moduledoc """
  Upload step that stores the data export in S3 (LocalStack).

  Instead of direct S3 presigned URLs, this step stores the S3 key
  and the download is proxied through an API endpoint that:
  1. Validates the request
  2. Streams the file from S3
  3. Records when the file was downloaded
  """
  require Logger

  alias RoutingExamples.ProcessManager.S3Client

  @doc """
  Execute the upload step.
  """
  def execute(instance) do
    # Ensure bucket exists
    S3Client.ensure_bucket()

    # Get packaging result from intermediate results
    packaging_result = Map.get(instance.intermediate_results, "packaging", %{})
    packaging_data = Map.get(packaging_result, :data, %{})

    zip_filename = Map.get(packaging_data, :zip_filename, "export.zip")

    user_id = Map.get(instance.context, :id, "unknown")
    correlation_id = instance.correlation_id

    # S3 key structure
    s3_key = "exports/#{user_id}/#{zip_filename}"

    # Create actual ZIP content from gathered data
    zip_content = create_zip_content(instance)
    size_bytes = byte_size(zip_content)

    Logger.info("Uploading #{size_bytes} bytes to S3 for process #{correlation_id}")

    # Upload to S3
    case S3Client.upload(zip_content, s3_key) do
      {:ok, _key} ->
        # Don't generate presigned URL - we'll use our own API endpoint
        # This allows us to track downloads
        download_path = "/api/exports/#{correlation_id}/download"

        {:ok, %{
          bucket: S3Client.bucket(),
          key: s3_key,
          size_bytes: size_bytes,
          download_path: download_path,
          uploaded_at: DateTime.utc_now()
        }}

      {:error, reason} ->
        Logger.error("Failed to upload to S3: #{inspect(reason)}")
        {:error, "S3 upload failed: #{inspect(reason)}"}
    end
  end

  # Creates a real ZIP file from the gathered data
  defp create_zip_content(instance) do
    gathered_data = get_gathered_data(instance.intermediate_results)
    user_context = instance.context

    # Build files for the ZIP
    files = [
      # Metadata file
      {~c"metadata.json", Jason.encode!(%{
        export_id: instance.correlation_id,
        user_id: Map.get(user_context, :id),
        email: Map.get(user_context, :email),
        exported_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        data_sources: Map.keys(gathered_data)
      }, pretty: true)},

      # User context
      {~c"user_info.json", Jason.encode!(%{
        user: user_context,
        scenario: Map.get(user_context, :scenario_id)
      }, pretty: true)}
    ]

    # Add each gathered data source as a separate file
    data_files =
      Enum.map(gathered_data, fn {key, value} ->
        source = String.replace_prefix(key, "gather:", "")
        filename = "data/#{source}.json"
        content = Jason.encode!(value, pretty: true)
        {String.to_charlist(filename), content}
      end)

    # Create the ZIP
    all_files = files ++ data_files
    {:ok, {_filename, zip_binary}} = :zip.create("export.zip", all_files, [:memory])
    zip_binary
  end

  defp get_gathered_data(intermediate_results) do
    intermediate_results
    |> Enum.filter(fn {key, _value} -> String.starts_with?(key, "gather:") end)
    |> Enum.into(%{})
  end
end
