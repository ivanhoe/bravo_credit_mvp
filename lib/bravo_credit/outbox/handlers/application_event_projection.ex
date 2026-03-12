defmodule BravoCredit.Outbox.Handlers.ApplicationEventProjection do
  @moduledoc """
  Default handler for application-event outbox rows.

  The current implementation is intentionally light: it simulates a non-critical
  projection/notification side effect and marks the outbox row as dispatched.
  """

  @behaviour BravoCredit.Outbox.Handler

  require Logger

  alias BravoCredit.Outbox.Event

  @impl true
  def handle(%Event{} = event) do
    Logger.info(
      "dispatching application_event outbox item #{inspect(%{aggregate_type: event.aggregate_type, aggregate_id: event.aggregate_id, event_type: event.event_type})}"
    )

    :ok
  end
end
