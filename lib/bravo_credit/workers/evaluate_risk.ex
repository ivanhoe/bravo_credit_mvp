defmodule BravoCredit.Workers.EvaluateRisk do
  @moduledoc """
  Evaluates provider-enriched applications and persists the first risk decision.
  """

  use Oban.Worker, queue: :risk, max_attempts: 5

  alias BravoCredit.Error
  alias BravoCredit.Pipelines.EvaluateRisk, as: EvaluateRiskPipeline

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"application_id" => application_id} = args}) do
    request_id = Map.get(args, "request_id", Ecto.UUID.generate())

    case EvaluateRiskPipeline.call(application_id, request_id) do
      {:ok, _context} ->
        :ok

      {:error, %Error{retryable?: false} = error} ->
        {:discard, "#{error.code}: #{error.message}"}

      {:error, %Error{} = error} ->
        {:error, "#{error.code}: #{error.message}"}
    end
  end
end
