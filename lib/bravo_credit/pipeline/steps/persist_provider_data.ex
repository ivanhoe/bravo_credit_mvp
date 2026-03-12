defmodule BravoCredit.Pipeline.Steps.PersistProviderData do
  @moduledoc """
  Persists sanitized provider data, app event, outbox record, and next risk job atomically.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Applications.Application
  alias BravoCredit.Applications.ApplicationEvent
  alias BravoCredit.Errors
  alias BravoCredit.Outbox.Event, as: OutboxEvent
  alias BravoCredit.Repo
  alias BravoCredit.Workers.EvaluateRisk
  alias Ecto.Multi

  @impl true
  def call(%{application: %Application{} = application, provider_data: provider_data} = context) do
    multi =
      Multi.new()
      |> Multi.update(:application, provider_data_changeset(application, provider_data))
      |> Multi.insert(:application_event, &application_event_changeset(&1, context))
      |> Multi.insert(:outbox_event, &outbox_event_changeset(&1, context))
      |> Oban.insert(:evaluate_risk_job, &evaluate_risk_job(&1, context))

    case Repo.transaction(multi) do
      {:ok, %{application: updated_application, application_event: application_event}} ->
        {:ok,
         %{
           context
           | application: updated_application,
             events: [application_event | context.events]
         }}

      {:error, operation, reason, _changes_so_far} ->
        {:error,
         Errors.internal_error("Failed to persist provider data pipeline", %{
           operation: to_string(operation),
           reason: inspect(reason)
         })}
    end
  end

  defp provider_data_changeset(application, provider_data) do
    Application.update_changeset(application, %{
      banking_info: provider_data,
      status: :evaluating,
      risk_status: :provider_data_ready
    })
  end

  defp application_event_changeset(%{application: application}, context) do
    ApplicationEvent.changeset(%ApplicationEvent{}, %{
      application_id: application.id,
      event_type: "application.provider_data_received",
      actor: "worker.fetch_provider_data",
      payload: %{
        "application_id" => application.id,
        "country_code" => application.country_code,
        "request_id" => context.request_id,
        "status" => "evaluating"
      }
    })
  end

  defp outbox_event_changeset(%{application: application}, context) do
    OutboxEvent.changeset(%OutboxEvent{}, %{
      aggregate_type: "application",
      aggregate_id: application.id,
      event_type: "application.provider_data_received",
      payload: %{
        "application_id" => application.id,
        "country_code" => application.country_code,
        "request_id" => context.request_id
      }
    })
  end

  defp evaluate_risk_job(%{application: application}, context) do
    EvaluateRisk.new(%{
      "application_id" => application.id,
      "country_code" => application.country_code,
      "request_id" => context.request_id
    })
  end
end
