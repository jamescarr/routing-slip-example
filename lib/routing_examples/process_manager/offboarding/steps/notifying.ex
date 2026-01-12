defmodule RoutingExamples.ProcessManager.Offboarding.Steps.Notifying do
  @moduledoc """
  Notification step that sends the download link to the user.

  Uses the signed URL from the upload step to compose an email
  notification to the user.
  """

  @doc """
  Execute the notification step.
  """
  def execute(instance) do
    # Get upload result from intermediate results
    upload_result = Map.get(instance.intermediate_results, "uploading", %{})
    upload_data = Map.get(upload_result, :data, %{})

    signed_url = Map.get(upload_data, :signed_url, "")
    expires_at = Map.get(upload_data, :expires_at, DateTime.utc_now())

    user_email = Map.get(instance.context, :email, "unknown@example.com")
    user_name = Map.get(instance.context, :name, "User")

    # Simulate email sending
    Process.sleep(200 + :rand.uniform(300))

    {:ok, %{
      notification_type: :email,
      recipient: user_email,
      recipient_name: user_name,
      subject: "Your GDPR Data Export is Ready",
      download_url: signed_url,
      expires_at: expires_at,
      sent_at: DateTime.utc_now(),
      message_id: generate_message_id()
    }}
  end

  defp generate_message_id do
    "email_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
