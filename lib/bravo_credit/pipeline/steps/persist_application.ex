defmodule BravoCredit.Pipeline.Steps.PersistApplication do
  @moduledoc """
  Persists the application, audit event, outbox record, and provider job in one transaction.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Applications.ApplicationEvent
  alias BravoCredit.Errors
  alias BravoCredit.Outbox.Event, as: OutboxEvent
  alias BravoCredit.Repo
  alias BravoCredit.Workers.FetchProviderData
  alias Ecto.Multi

  @impl true
  def call(%{application_changeset: application_changeset} = context) do
    multi =
      Multi.new()
      |> Multi.insert(:application, application_changeset)
      |> Multi.insert(:application_event, &application_event_changeset(&1, context))
      |> Multi.insert(:outbox_event, &outbox_event_changeset(&1, context))
      |> Oban.insert(:fetch_provider_data_job, &fetch_provider_data_job(&1, context))

    case Repo.transaction(multi) do
      {:ok, %{application: application, application_event: application_event}} ->
        {:ok, %{context | application: application, events: [application_event | context.events]}}

      {:error, :application, changeset, _changes_so_far} ->
        {:error, translate_application_error(changeset)}

      {:error, operation, reason, _changes_so_far} ->
        {:error,
         Errors.internal_error("Failed to persist create application pipeline", %{
           operation: to_string(operation),
           reason: inspect(reason)
         })}
    end
  end

  defp application_event_changeset(%{application: application}, context) do
    ApplicationEvent.changeset(%ApplicationEvent{}, %{
      application_id: application.id,
      event_type: "application.created",
      actor: actor_to_string(context.actor),
      payload: %{
        "application_id" => application.id,
        "country_code" => application.country_code,
        "request_id" => context.request_id,
        "status" => Atom.to_string(application.status)
      }
    })
  end

  defp outbox_event_changeset(%{application: application}, context) do
    OutboxEvent.changeset(%OutboxEvent{}, %{
      aggregate_type: "application",
      aggregate_id: application.id,
      event_type: "application.created",
      payload: %{
        "application_id" => application.id,
        "country_code" => application.country_code,
        "request_id" => context.request_id
      }
    })
  end

  defp fetch_provider_data_job(%{application: application}, context) do
    FetchProviderData.new(%{
      "application_id" => application.id,
      "country_code" => application.country_code,
      "request_id" => context.request_id
    })
  end

  defp translate_application_error(changeset) do
    if Keyword.has_key?(changeset.errors, :document_hash) do
      Errors.duplicate_document(Ecto.Changeset.get_field(changeset, :document_hash))
    else
      Errors.invalid_params(%{fields: errors_on(changeset)})
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp actor_to_string(actor) when is_binary(actor), do: actor
  defp actor_to_string(actor) when is_atom(actor), do: Atom.to_string(actor)
  defp actor_to_string(%{id: id}) when is_binary(id), do: id
  defp actor_to_string(_actor), do: "system"
end
