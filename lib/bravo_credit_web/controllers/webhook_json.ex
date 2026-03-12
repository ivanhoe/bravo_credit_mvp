defmodule BravoCreditWeb.WebhookJSON do
  @moduledoc """
  JSON rendering helpers for incoming webhook resources.
  """

  alias BravoCredit.Webhooks.WebhookEvent

  def show(%{webhook_event: webhook_event}) do
    %{data: data(webhook_event)}
  end

  defp data(%WebhookEvent{} = webhook_event) do
    %{
      id: webhook_event.id,
      source: webhook_event.source,
      event_type: webhook_event.event_type,
      status: webhook_event.status
    }
  end
end
