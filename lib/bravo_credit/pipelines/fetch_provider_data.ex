defmodule BravoCredit.Pipelines.FetchProviderData do
  @moduledoc """
  Worker pipeline that fetches external provider data and persists a sanitized snapshot.
  """

  alias BravoCredit.Errors
  alias BravoCredit.Pipeline.Context
  alias BravoCredit.Pipeline.Runner
  alias BravoCredit.Pipeline.Steps

  @steps [
    Steps.LoadApplication,
    Steps.MarkProviderProcessing,
    Steps.FetchProviderPayload,
    Steps.SanitizeProviderPayload,
    Steps.PersistProviderData
  ]

  @spec call(Ecto.UUID.t(), Ecto.UUID.t() | nil) ::
          {:ok, Context.t()} | {:error, BravoCredit.Error.t()}
  def call(application_id, request_id \\ Ecto.UUID.generate())

  def call(application_id, request_id) when is_binary(application_id) do
    %Context{
      request_id: request_id,
      actor: "worker.fetch_provider_data",
      raw_params: %{"application_id" => application_id}
    }
    |> Runner.run(@steps)
  end

  def call(_application_id, _request_id) do
    {:error, Errors.invalid_params(%{fields: %{application_id: ["must be a string"]}})}
  end
end
