defmodule RoutingExamples.ProcessManager.S3Client do
  @moduledoc """
  S3 client wrapper for LocalStack integration.
  Handles bucket operations, file uploads, and signed URL generation.
  """
  require Logger

  @doc """
  Returns the configured S3 bucket name.
  """
  def bucket do
    Application.get_env(:routing_examples, :s3, [])
    |> Keyword.get(:bucket, "gdpr-exports")
  end

  @doc """
  Returns the signed URL expiry time in seconds.
  """
  def signed_url_expiry do
    Application.get_env(:routing_examples, :s3, [])
    |> Keyword.get(:signed_url_expiry, 7 * 24 * 60 * 60)
  end

  @doc """
  Ensures the S3 bucket exists, creating it if necessary.
  """
  def ensure_bucket do
    case ExAws.S3.head_bucket(bucket()) |> ExAws.request() do
      {:ok, _} ->
        Logger.debug("S3 bucket '#{bucket()}' already exists")
        :ok

      {:error, {:http_error, 404, _}} ->
        Logger.info("Creating S3 bucket '#{bucket()}'")
        create_bucket()

      {:error, reason} ->
        Logger.error("Failed to check bucket: #{inspect(reason)}")
        # Try creating anyway
        create_bucket()
    end
  end

  defp create_bucket do
    case ExAws.S3.put_bucket(bucket(), "us-east-1") |> ExAws.request() do
      {:ok, _} ->
        Logger.info("Created S3 bucket '#{bucket()}'")
        :ok

      {:error, {:http_error, 409, _}} ->
        # Bucket already exists (race condition)
        :ok

      {:error, reason} ->
        Logger.error("Failed to create bucket: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Uploads content to S3.
  Returns {:ok, s3_key} or {:error, reason}.
  """
  def upload(content, key) when is_binary(content) and is_binary(key) do
    Logger.info("Uploading #{byte_size(content)} bytes to s3://#{bucket()}/#{key}")

    case ExAws.S3.put_object(bucket(), key, content) |> ExAws.request() do
      {:ok, _} ->
        Logger.info("Successfully uploaded to #{key}")
        {:ok, key}

      {:error, reason} ->
        Logger.error("Failed to upload to S3: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Downloads content from S3.
  Returns {:ok, binary_content} or {:error, reason}.
  """
  def download(key) when is_binary(key) do
    Logger.info("Downloading s3://#{bucket()}/#{key}")

    case ExAws.S3.get_object(bucket(), key) |> ExAws.request() do
      {:ok, %{body: body}} ->
        {:ok, body}

      {:error, reason} ->
        Logger.error("Failed to download from S3: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Checks if an object exists in S3.
  """
  def exists?(key) when is_binary(key) do
    case ExAws.S3.head_object(bucket(), key) |> ExAws.request() do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Generates metadata about an S3 object.
  """
  def head_object(key) when is_binary(key) do
    case ExAws.S3.head_object(bucket(), key) |> ExAws.request() do
      {:ok, %{headers: headers}} ->
        content_length =
          headers
          |> Enum.find(fn {k, _v} -> String.downcase(k) == "content-length" end)
          |> case do
            {_, length} -> String.to_integer(length)
            nil -> 0
          end

        content_type =
          headers
          |> Enum.find(fn {k, _v} -> String.downcase(k) == "content-type" end)
          |> case do
            {_, type} -> type
            nil -> "application/octet-stream"
          end

        {:ok, %{content_length: content_length, content_type: content_type}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a presigned download URL for an S3 object.
  The URL will be valid for the configured expiry time.
  """
  def presigned_download_url(key) when is_binary(key) do
    # ExAws.S3.presigned_url returns a URL string directly
    config = ExAws.Config.new(:s3)
    expiry_seconds = signed_url_expiry()

    case ExAws.S3.presigned_url(config, :get, bucket(), key, expires_in: expiry_seconds) do
      {:ok, url} ->
        {:ok, url, DateTime.add(DateTime.utc_now(), expiry_seconds, :second)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
