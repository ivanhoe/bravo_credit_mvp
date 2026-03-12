defmodule BravoCredit.Pipeline.Steps.PersistRiskDecision do
  @moduledoc """
  Persists the final risk decision, audit event, and outbox entry atomically.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Applications.Application
  alias BravoCredit.Applications.ApplicationEvent
  alias BravoCredit.Errors
  alias BravoCredit.Outbox.Event, as: OutboxEvent
  alias BravoCredit.Repo
  alias Ecto.Multi

  @impl true
  def call(%{application: %Application{} = application, decision: decision} = context)
      when is_map(decision) do
    multi =
      Multi.new()
      |> Multi.update(:application, decision_changeset(application, decision))
      |> Multi.insert(:application_event, &application_event_changeset(&1, context))
      |> Multi.insert(:outbox_event, &outbox_event_changeset(&1, context))

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
         Errors.internal_error("Failed to persist risk decision pipeline", %{
           operation: to_string(operation),
           reason: inspect(reason)
         })}
    end
  end

  defp decision_changeset(application, decision) do
    Application.update_changeset(application, %{
      status: decision.outcome,
      risk_status: decision.risk_status,
      risk_score: decision.risk_score
    })
  end

  defp application_event_changeset(%{application: application}, context) do
    ApplicationEvent.changeset(%ApplicationEvent{}, %{
      application_id: application.id,
      event_type: "application.risk_evaluated",
      actor: "worker.evaluate_risk",
      payload: %{
        "application_id" => application.id,
        "country_code" => application.country_code,
        "request_id" => context.request_id,
        "outcome" => Atom.to_string(context.decision.outcome),
        "risk_score" => context.decision.risk_score,
        "risk_status" => Atom.to_string(context.decision.risk_status),
        "reason" => normalize_reason(context.decision[:reason])
      }
    })
  end

  defp outbox_event_changeset(%{application: application}, context) do
    OutboxEvent.changeset(%OutboxEvent{}, %{
      aggregate_type: "application",
      aggregate_id: application.id,
      event_type: "application.risk_evaluated",
      payload: %{
        "application_id" => application.id,
        "country_code" => application.country_code,
        "request_id" => context.request_id,
        "outcome" => Atom.to_string(context.decision.outcome)
      }
    })
  end

  defp normalize_reason(nil), do: nil

  defp normalize_reason(%{code: _, message: _, details: _} = reason) do
    %{
      "code" => reason.code,
      "message" => reason.message,
      "details" => reason.details
    }
  end

  defp normalize_reason(%BravoCredit.Error{} = error) do
    %{
      "code" => error.code,
      "message" => error.message,
      "details" => error.details
    }
  end
end
