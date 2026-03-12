defmodule BravoCredit.Webhooks.Processor do
  @moduledoc """
  Applies incoming provider webhook effects to an application aggregate.
  """

  alias BravoCredit.Applications
  alias BravoCredit.Applications.Application
  alias BravoCredit.Applications.ApplicationEvent
  alias BravoCredit.Errors
  alias BravoCredit.Repo
  alias BravoCredit.Webhooks
  alias BravoCredit.Webhooks.WebhookEvent
  alias Ecto.Multi

  @allowed_transitions %{
    pending: [:approved, :rejected, :in_review],
    provider_processing: [:approved, :rejected, :in_review],
    evaluating: [:approved, :rejected, :in_review],
    in_review: [:approved, :rejected],
    approved: [],
    rejected: [],
    cancelled: []
  }

  @type process_result :: {:ok, map()} | {:error, BravoCredit.Error.t()}

  @spec call(Ecto.UUID.t(), Ecto.UUID.t()) :: process_result()
  def call(webhook_event_id, request_id \\ Ecto.UUID.generate())

  def call(webhook_event_id, request_id)
      when is_binary(webhook_event_id) and is_binary(request_id) do
    with {:ok, webhook_event} <- fetch_webhook_event(webhook_event_id),
         {:ok, processing_event} <- Webhooks.mark_processing(webhook_event) do
      maybe_process(processing_event, request_id)
    end
  end

  def call(_webhook_event_id, _request_id) do
    {:error, Errors.invalid_params(%{fields: %{webhook_event_id: ["is invalid"]}})}
  end

  defp maybe_process(%WebhookEvent{status: :processed} = webhook_event, _request_id) do
    {:ok, %{webhook_event: webhook_event, application: nil, skipped?: true}}
  end

  defp maybe_process(%WebhookEvent{} = webhook_event, request_id) do
    with {:ok, application_id} <- extract_application_id(webhook_event),
         {:ok, application} <- load_application(application_id),
         {:ok, effect} <- resolve_effect(webhook_event, application) do
      persist_effect(webhook_event, application, effect, request_id)
    end
  end

  defp fetch_webhook_event(webhook_event_id) do
    case Webhooks.get_event(webhook_event_id) do
      %WebhookEvent{} = webhook_event -> {:ok, webhook_event}
      nil -> {:error, Errors.webhook_event_not_found(webhook_event_id)}
    end
  end

  defp extract_application_id(%WebhookEvent{payload: %{"application_id" => application_id}})
       when is_binary(application_id) do
    case Ecto.UUID.cast(application_id) do
      {:ok, cast_application_id} ->
        {:ok, cast_application_id}

      :error ->
        {:error,
         Errors.invalid_params(%{fields: %{"application_id" => ["must be a valid UUID"]}})}
    end
  end

  defp extract_application_id(%WebhookEvent{}) do
    {:error, Errors.invalid_params(%{fields: %{"application_id" => ["is required"]}})}
  end

  defp load_application(application_id) do
    case Applications.get(application_id) do
      %Application{} = application -> {:ok, application}
      nil -> {:error, Errors.application_not_found(application_id)}
    end
  end

  defp resolve_effect(
         %WebhookEvent{event_type: "provider.application_approved"} = webhook_event,
         application
       ) do
    build_effect(webhook_event, application, :approved, :approved)
  end

  defp resolve_effect(
         %WebhookEvent{event_type: "provider.application_rejected"} = webhook_event,
         application
       ) do
    build_effect(webhook_event, application, :rejected, :rejected)
  end

  defp resolve_effect(
         %WebhookEvent{event_type: "provider.manual_review_requested"} = webhook_event,
         application
       ) do
    build_effect(webhook_event, application, :in_review, :manual_review)
  end

  defp resolve_effect(%WebhookEvent{event_type: event_type}, _application) do
    {:error, Errors.unsupported_webhook_event(event_type)}
  end

  defp build_effect(webhook_event, application, target_state, risk_status) do
    if target_state == application.status or
         target_state in Map.get(@allowed_transitions, application.status, []) do
      {:ok,
       %{
         current_state: application.status,
         target_state: target_state,
         risk_status: risk_status,
         state_changed?: application.status != target_state,
         reason: Map.get(webhook_event.payload, "reason", webhook_event.event_type),
         external_event_type: webhook_event.event_type
       }}
    else
      {:error, Errors.invalid_transition(application.status, target_state)}
    end
  end

  defp persist_effect(webhook_event, application, effect, request_id) do
    multi =
      Multi.new()
      |> Multi.run(:application, fn repo, _changes ->
        application
        |> application_changeset(effect, webhook_event, request_id)
        |> repo.update()
      end)
      |> Multi.insert(:webhook_received_event, fn %{application: updated_application} ->
        webhook_received_event_changeset(updated_application, webhook_event, request_id)
      end)
      |> maybe_insert_state_changed_event(effect, webhook_event, request_id)
      |> Multi.update(:webhook_event, fn %{application: updated_application} ->
        WebhookEvent.changeset(webhook_event, %{
          status: :processed,
          application_id: updated_application.id,
          error_code: nil,
          error_message: nil
        })
      end)

    case Repo.transaction(multi) do
      {:ok, %{application: updated_application, webhook_event: updated_webhook_event} = changes} ->
        {:ok,
         %{
           application: updated_application,
           webhook_event: updated_webhook_event,
           events: collect_events(changes)
         }}

      {:error, operation, reason, _changes_so_far} ->
        {:error,
         Errors.internal_error("Failed to persist incoming webhook effect", %{
           operation: to_string(operation),
           reason: inspect(reason)
         })}
    end
  end

  defp application_changeset(application, effect, webhook_event, request_id) do
    metadata =
      Map.merge(application.metadata || %{}, %{
        "last_webhook_event_id" => webhook_event.id,
        "last_webhook_event_type" => webhook_event.event_type,
        "last_webhook_idempotency_key" => webhook_event.idempotency_key,
        "last_webhook_request_id" => request_id
      })

    Application.update_changeset(application, %{
      status: effect.target_state,
      risk_status: effect.risk_status,
      metadata: metadata
    })
  end

  defp webhook_received_event_changeset(application, webhook_event, request_id) do
    ApplicationEvent.changeset(%ApplicationEvent{}, %{
      application_id: application.id,
      event_type: "webhook.received",
      actor: "webhook:provider",
      payload: %{
        "application_id" => application.id,
        "country_code" => application.country_code,
        "external_event_type" => webhook_event.event_type,
        "idempotency_key" => webhook_event.idempotency_key,
        "request_id" => request_id,
        "source" => webhook_event.source,
        "webhook_event_id" => webhook_event.id
      }
    })
  end

  defp maybe_insert_state_changed_event(
         multi,
         %{state_changed?: false},
         _webhook_event,
         _request_id
       ),
       do: multi

  defp maybe_insert_state_changed_event(multi, effect, webhook_event, request_id) do
    Multi.insert(multi, :state_changed_event, fn %{application: application} ->
      ApplicationEvent.changeset(%ApplicationEvent{}, %{
        application_id: application.id,
        event_type: "application.state_changed",
        actor: "webhook:provider",
        payload: %{
          "application_id" => application.id,
          "country_code" => application.country_code,
          "from" => Atom.to_string(effect.current_state),
          "to" => Atom.to_string(effect.target_state),
          "reason" => effect.reason,
          "request_id" => request_id,
          "source" => webhook_event.source,
          "webhook_event_id" => webhook_event.id
        }
      })
    end)
  end

  defp collect_events(changes) do
    changes
    |> Map.take([:webhook_received_event, :state_changed_event])
    |> Map.values()
  end
end
