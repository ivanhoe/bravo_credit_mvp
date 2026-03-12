defmodule BravoCredit.Workers.FetchProviderData do
  @moduledoc """
  Fetches simulated provider data and persists a sanitized snapshot for risk evaluation.
  """

  use Oban.Worker, queue: :providers, max_attempts: 5

  alias BravoCredit.Error
  alias BravoCredit.Pipelines.FetchProviderData, as: FetchProviderDataPipeline

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"application_id" => application_id} = args}) do
    request_id = Map.get(args, "request_id", Ecto.UUID.generate())

    case FetchProviderDataPipeline.call(application_id, request_id) do
      {:ok, _context} ->
        :ok

      {:error, %Error{retryable?: false} = error} ->
        {:discard, "#{error.code}: #{error.message}"}

      {:error, %Error{} = error} ->
        {:error, "#{error.code}: #{error.message}"}
    end
  end
end
