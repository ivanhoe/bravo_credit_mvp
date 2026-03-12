defmodule BravoCredit.Webhooks do
  @moduledoc """
  Public services for receiving and tracking incoming provider webhooks.
  """

  alias BravoCredit.Errors
  alias BravoCredit.Repo
  alias BravoCredit.Webhooks.Processor
  alias BravoCredit.Webhooks.WebhookEvent
  alias BravoCredit.Workers.ProcessIncomingWebhook
  alias Ecto.Multi

  @source "provider"
  @supported_event_types [
    "provider.application_approved",
    "provider.application_rejected",
    "provider.manual_review_requested"
  ]

  @type receive_result :: {:ok, WebhookEvent.t()} | {:error, BravoCredit.Error.t()}

  @spec receive_provider(map()) :: receive_result()
  def receive_provider(params) when is_map(params) do
    with {:ok, attrs} <- build_receive_attrs(params) do
      request_id = Ecto.UUID.generate()

      multi =
        Multi.new()
        |> Multi.insert(:webhook_event, WebhookEvent.changeset(%WebhookEvent{}, attrs))
        |> Oban.insert(
          :process_incoming_webhook_job,
          &process_incoming_webhook_job(&1, request_id)
        )

      case Repo.transaction(multi) do
        {:ok, %{webhook_event: webhook_event}} ->
          {:ok, webhook_event}

        {:error, :webhook_event, changeset, _changes_so_far} ->
          {:error, translate_receive_error(changeset, attrs)}

        {:error, operation, reason, _changes_so_far} ->
          {:error,
           Errors.internal_error("Failed to persist incoming webhook", %{
             operation: to_string(operation),
             reason: inspect(reason)
           })}
      end
    end
  end

  def receive_provider(_params) do
    {:error, Errors.invalid_params(%{fields: %{base: ["must be a map"]}})}
  end

  @spec process(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, map()} | {:error, BravoCredit.Error.t()}
  def process(webhook_event_id, request_id \\ Ecto.UUID.generate()) do
    Processor.call(webhook_event_id, request_id)
  end

  @spec get_event(Ecto.UUID.t()) :: WebhookEvent.t() | nil
  def get_event(webhook_event_id), do: Repo.get(WebhookEvent, webhook_event_id)

  @spec mark_processing(WebhookEvent.t()) ::
          {:ok, WebhookEvent.t()} | {:error, Ecto.Changeset.t()}
  def mark_processing(%WebhookEvent{status: :processed} = webhook_event), do: {:ok, webhook_event}

  def mark_processing(%WebhookEvent{} = webhook_event) do
    webhook_event
    |> WebhookEvent.changeset(%{
      status: :processing,
      error_code: nil,
      error_message: nil
    })
    |> Repo.update()
  end

  @spec record_failure(WebhookEvent.t(), BravoCredit.Error.t()) ::
          {:ok, WebhookEvent.t()} | {:error, Ecto.Changeset.t()}
  def record_failure(%WebhookEvent{} = webhook_event, %BravoCredit.Error{} = error) do
    status = if(error.retryable? == true, do: :received, else: :failed)

    webhook_event
    |> WebhookEvent.changeset(%{
      status: status,
      error_code: error.code,
      error_message: error.message
    })
    |> Repo.update()
  end

  defp build_receive_attrs(params) do
    event_type = normalize_string(params["event_type"])
    idempotency_key = normalize_string(params["idempotency_key"])
    application_id = normalize_string(params["application_id"])

    errors =
      %{}
      |> maybe_put_error("event_type", validate_event_type(event_type))
      |> maybe_put_error("idempotency_key", validate_required(idempotency_key))
      |> maybe_put_error("application_id", validate_application_id(application_id))

    if map_size(errors) == 0 do
      {:ok,
       %{
         source: @source,
         idempotency_key: idempotency_key,
         event_type: event_type,
         payload: params,
         status: :received
       }}
    else
      {:error, Errors.invalid_params(%{fields: errors})}
    end
  end

  defp process_incoming_webhook_job(%{webhook_event: webhook_event}, request_id) do
    ProcessIncomingWebhook.new(%{
      "webhook_event_id" => webhook_event.id,
      "request_id" => request_id
    })
  end

  defp translate_receive_error(changeset, attrs) do
    if duplicate_constraint_error?(changeset) do
      Errors.duplicate_webhook_event(attrs.source, attrs.idempotency_key)
    else
      Errors.invalid_params(%{fields: errors_on(changeset)})
    end
  end

  defp validate_event_type(nil), do: ["is required"]

  defp validate_event_type(event_type) do
    if event_type in @supported_event_types do
      nil
    else
      ["is not supported"]
    end
  end

  defp validate_required(nil), do: ["is required"]
  defp validate_required(_value), do: nil

  defp validate_application_id(nil), do: ["is required"]

  defp validate_application_id(application_id) do
    case Ecto.UUID.cast(application_id) do
      {:ok, _application_id} -> nil
      :error -> ["must be a valid UUID"]
    end
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(_value), do: nil

  defp maybe_put_error(errors, _field, nil), do: errors
  defp maybe_put_error(errors, field, messages), do: Map.put(errors, field, messages)

  defp duplicate_constraint_error?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_message, opts}} ->
      opts[:constraint] == :unique
    end)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
