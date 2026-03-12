defmodule BravoCredit.Monitoring.Broadcaster do
  @moduledoc """
  PubSub notifications used by the monitoring LiveViews.
  """

  alias BravoCredit.Applications.Application
  alias BravoCredit.Outbox.Event, as: OutboxEvent

  @dashboard_topic "monitoring:dashboard"

  @spec subscribe_dashboard() :: :ok | {:error, term()}
  def subscribe_dashboard do
    Phoenix.PubSub.subscribe(BravoCredit.PubSub, @dashboard_topic)
  end

  @spec subscribe_application(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_application(application_id) when is_binary(application_id) do
    Phoenix.PubSub.subscribe(BravoCredit.PubSub, application_topic(application_id))
  end

  @spec broadcast_application(Application.t(), String.t(), map()) :: :ok
  def broadcast_application(%Application{} = application, event_type, metadata \\ %{}) do
    broadcast(application.id, %{
      application_id: application.id,
      country_code: application.country_code,
      event_type: event_type,
      status: Atom.to_string(application.status),
      risk_status: Atom.to_string(application.risk_status),
      at: DateTime.utc_now()
    })
    |> merge_and_broadcast(metadata)
  end

  @spec broadcast_application_id(Ecto.UUID.t(), String.t(), map()) :: :ok
  def broadcast_application_id(application_id, event_type, metadata \\ %{})
      when is_binary(application_id) do
    broadcast(application_id, %{
      application_id: application_id,
      event_type: event_type,
      at: DateTime.utc_now()
    })
    |> merge_and_broadcast(metadata)
  end

  @spec broadcast_outbox_event(OutboxEvent.t()) :: :ok
  def broadcast_outbox_event(%OutboxEvent{} = outbox_event) do
    case extract_application_id(outbox_event) do
      nil ->
        :ok

      application_id ->
        broadcast_application_id(application_id, "outbox.updated", %{
          outbox_event_id: outbox_event.id,
          outbox_event_type: outbox_event.event_type,
          outbox_status: Atom.to_string(outbox_event.status)
        })
    end
  end

  defp merge_and_broadcast({application_id, payload}, metadata) do
    merged_payload = Map.merge(payload, metadata)

    Phoenix.PubSub.broadcast(
      BravoCredit.PubSub,
      @dashboard_topic,
      {:monitoring_event, merged_payload}
    )

    Phoenix.PubSub.broadcast(
      BravoCredit.PubSub,
      application_topic(application_id),
      {:monitoring_event, merged_payload}
    )

    :ok
  end

  defp broadcast(application_id, payload), do: {application_id, payload}

  defp application_topic(application_id), do: "monitoring:application:" <> application_id

  defp extract_application_id(%OutboxEvent{
         aggregate_type: "application",
         aggregate_id: application_id
       })
       when is_binary(application_id),
       do: application_id

  defp extract_application_id(%OutboxEvent{payload: %{"application_id" => application_id}})
       when is_binary(application_id),
       do: application_id

  defp extract_application_id(%OutboxEvent{}), do: nil
end
