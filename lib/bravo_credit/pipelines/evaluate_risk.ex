defmodule BravoCredit.Pipelines.EvaluateRisk do
  @moduledoc """
  Worker pipeline that evaluates provider-dependent rules and decides the initial application outcome.
  """

  alias BravoCredit.Errors
  alias BravoCredit.Pipeline.Context
  alias BravoCredit.Pipeline.Runner
  alias BravoCredit.Pipeline.Steps

  @steps [
    Steps.LoadApplication,
    Steps.EvaluateProviderDependentRules,
    Steps.CalculateRiskScore,
    Steps.DecideOutcome,
    Steps.PersistRiskDecision
  ]

  @spec call(Ecto.UUID.t(), Ecto.UUID.t() | nil) ::
          {:ok, Context.t()} | {:error, BravoCredit.Error.t()}
  def call(application_id, request_id \\ Ecto.UUID.generate())

  def call(application_id, request_id) when is_binary(application_id) do
    %Context{
      request_id: request_id,
      actor: "worker.evaluate_risk",
      raw_params: %{"application_id" => application_id}
    }
    |> Runner.run(@steps)
  end

  def call(_application_id, _request_id) do
    {:error, Errors.invalid_params(%{fields: %{application_id: ["must be a string"]}})}
  end
end
