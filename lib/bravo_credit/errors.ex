defmodule BravoCredit.Errors do
  @moduledoc """
  Factory helpers for the project's canonical error catalog.
  """

  alias BravoCredit.Error

  @type option ::
          {:details, map()}
          | {:http_status, pos_integer()}
          | {:retryable?, boolean()}
          | {:source, atom()}
          | {:step, atom() | String.t()}

  @spec new(String.t(), String.t(), [option()]) :: Error.t()
  def new(code, message, opts \\ []) do
    %Error{
      code: code,
      message: message,
      details: Keyword.get(opts, :details, %{}),
      http_status: Keyword.get(opts, :http_status),
      source: Keyword.get(opts, :source),
      step: Keyword.get(opts, :step),
      retryable?: Keyword.get(opts, :retryable?)
    }
  end

  @spec invalid_params(map()) :: Error.t()
  def invalid_params(details \\ %{}) do
    new("validation.invalid_params", "Request payload is invalid",
      http_status: 400,
      source: :validation,
      retryable?: false,
      details: details
    )
  end

  @spec unsupported_country(String.t()) :: Error.t()
  def unsupported_country(country_code) do
    new("country.unsupported", "Country is not supported",
      http_status: 422,
      source: :domain,
      retryable?: false,
      details: %{country_code: country_code}
    )
  end

  @spec invalid_document_format(String.t()) :: Error.t()
  def invalid_document_format(field \\ "document_id") do
    new("document.invalid_format", "Document format is invalid",
      http_status: 422,
      source: :validation,
      retryable?: false,
      details: %{field: field}
    )
  end

  @spec initial_rules_rejected(String.t(), map()) :: Error.t()
  def initial_rules_rejected(
        message \\ "Initial business rules rejected the request",
        details \\ %{}
      ) do
    new("rules.initial_rejected", message,
      http_status: 422,
      source: :domain,
      retryable?: false,
      details: details
    )
  end

  @spec duplicate_document(String.t() | nil) :: Error.t()
  def duplicate_document(document_hash \\ nil) do
    new("application.duplicate_document", "Document is already registered",
      http_status: 409,
      source: :domain,
      retryable?: false,
      details: maybe_put(%{}, :document_hash, document_hash)
    )
  end

  @spec application_not_found(Ecto.UUID.t() | nil) :: Error.t()
  def application_not_found(application_id \\ nil) do
    new("application.not_found", "Application was not found",
      http_status: 404,
      source: :domain,
      retryable?: false,
      details: maybe_put(%{}, :application_id, application_id)
    )
  end

  @spec invalid_transition(atom() | String.t(), atom() | String.t()) :: Error.t()
  def invalid_transition(from, to) do
    new("state.invalid_transition", "State transition is invalid",
      http_status: 409,
      source: :domain,
      retryable?: false,
      details: %{from: from, to: to}
    )
  end

  @spec unauthenticated() :: Error.t()
  def unauthenticated do
    new("auth.unauthenticated", "Authentication is required",
      http_status: 401,
      source: :auth,
      retryable?: false
    )
  end

  @spec forbidden_country(String.t() | nil) :: Error.t()
  def forbidden_country(country_code \\ nil) do
    new("auth.forbidden_country", "You do not have access to the requested country",
      http_status: 403,
      source: :auth,
      retryable?: false,
      details: maybe_put(%{}, :country_code, country_code)
    )
  end

  @spec provider_unreachable(map()) :: Error.t()
  def provider_unreachable(details \\ %{}) do
    new("provider.unreachable", "Provider is temporarily unavailable",
      http_status: 503,
      source: :provider,
      retryable?: true,
      details: details
    )
  end

  @spec provider_invalid_response(map()) :: Error.t()
  def provider_invalid_response(details \\ %{}) do
    new("provider.invalid_response", "Provider returned an invalid response",
      http_status: 502,
      source: :provider,
      retryable?: false,
      details: details
    )
  end

  @spec duplicate_webhook_event(String.t(), String.t()) :: Error.t()
  def duplicate_webhook_event(source, idempotency_key) do
    new("webhook.duplicate_event", "Webhook event has already been processed",
      http_status: 409,
      source: :webhook,
      retryable?: false,
      details: %{source: source, idempotency_key: idempotency_key}
    )
  end

  @spec outbox_dispatch_failed(map()) :: Error.t()
  def outbox_dispatch_failed(details \\ %{}) do
    new("outbox.dispatch_failed", "Outbox dispatch failed",
      http_status: 503,
      source: :system,
      retryable?: true,
      details: details
    )
  end

  @spec internal_error(String.t(), map()) :: Error.t()
  def internal_error(message \\ "Internal server error", details \\ %{}) do
    new("system.internal_error", message,
      http_status: 500,
      source: :system,
      retryable?: false,
      details: details
    )
  end

  @spec with_step(Error.t(), atom() | String.t()) :: Error.t()
  def with_step(%Error{} = error, step), do: %{error | step: step}

  @spec to_exception(Error.t()) :: RuntimeError.t()
  def to_exception(%Error{} = error) do
    RuntimeError.exception("#{error.code}: #{error.message}")
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
