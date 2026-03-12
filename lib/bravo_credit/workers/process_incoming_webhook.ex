defmodule BravoCredit.Workers.ProcessIncomingWebhook do
  @moduledoc """
  Applies persisted provider webhooks to applications using the canonical webhook processor.
  """

  use Oban.Worker, queue: :webhooks, max_attempts: 5

  alias BravoCredit.Error
  alias BravoCredit.Webhooks
  alias BravoCredit.Webhooks.WebhookEvent

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"webhook_event_id" => webhook_event_id} = args}) do
    request_id = Map.get(args, "request_id", Ecto.UUID.generate())

    case Webhooks.process(webhook_event_id, request_id) do
      {:ok, _result} ->
        :ok

      {:error, %Error{retryable?: false} = error} ->
        record_failure(webhook_event_id, error)
        {:discard, "#{error.code}: #{error.message}"}

      {:error, %Error{} = error} ->
        record_failure(webhook_event_id, error)
        {:error, "#{error.code}: #{error.message}"}
    end
  end

  defp record_failure(webhook_event_id, %Error{} = error) do
    case Webhooks.get_event(webhook_event_id) do
      %WebhookEvent{} = webhook_event ->
        _ = Webhooks.record_failure(webhook_event, error)
        :ok

      nil ->
        :ok
    end
  end
end
