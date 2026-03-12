defmodule BravoCredit.Pipeline.Steps.PersistTransition do
  @moduledoc """
  Persists a manual state transition and audit event atomically.

  The outbox row is created by the database trigger on `application_events`.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Applications.Application
  alias BravoCredit.Applications.ApplicationEvent
  alias BravoCredit.Errors
  alias BravoCredit.Repo
  alias Ecto.Multi

  @impl true
  def call(
        %{
          application: %Application{} = application,
          actor: actor,
          decision: %{target_state: target_state}
        } = context
      ) do
    multi =
      Multi.new()
      |> Multi.update(:application, transition_changeset(application, target_state))
      |> Multi.insert(:application_event, &application_event_changeset(&1, actor, context))

    case Repo.transaction(multi) do
      {:ok, %{application: updated_application, application_event: application_event}} ->
        {:ok,
         %{
           context
           | application: updated_application,
             events: [application_event | context.events]
         }}

      {:error, :application, %Ecto.Changeset{} = changeset, _changes_so_far} ->
        if Keyword.has_key?(changeset.errors, :lock_version) do
          {:error, Errors.invalid_transition(application.status, target_state)}
        else
          {:error, Errors.invalid_params(%{fields: errors_on(changeset)})}
        end

      {:error, operation, reason, _changes_so_far} ->
        {:error,
         Errors.internal_error("Failed to persist manual state transition", %{
           operation: to_string(operation),
           reason: inspect(reason)
         })}
    end
  rescue
    Ecto.StaleEntryError ->
      {:error, Errors.invalid_transition(application.status, target_state)}
  end

  defp transition_changeset(application, target_state) do
    Application.update_changeset(application, %{
      status: target_state,
      risk_status: target_risk_status(application, target_state)
    })
  end

  defp target_risk_status(_application, :approved), do: :approved
  defp target_risk_status(_application, :rejected), do: :rejected
  defp target_risk_status(_application, :in_review), do: :manual_review
  defp target_risk_status(application, :cancelled), do: application.risk_status
  defp target_risk_status(application, _state), do: application.risk_status

  defp application_event_changeset(%{application: application}, actor, context) do
    ApplicationEvent.changeset(%ApplicationEvent{}, %{
      application_id: application.id,
      event_type: "application.state_changed",
      actor: actor_to_string(actor),
      payload: %{
        "application_id" => application.id,
        "country_code" => application.country_code,
        "request_id" => context.request_id,
        "to_state" => Atom.to_string(context.decision.target_state),
        "risk_status" =>
          Atom.to_string(target_risk_status(application, context.decision.target_state))
      }
    })
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp actor_to_string(%{id: id}) when is_binary(id), do: id
  defp actor_to_string(actor) when is_binary(actor), do: actor
  defp actor_to_string(actor) when is_atom(actor), do: Atom.to_string(actor)
  defp actor_to_string(_actor), do: "system"
end
