defmodule BravoCredit.Pipeline.Steps.EvaluateProviderDependentRules do
  @moduledoc """
  Evaluates provider-dependent business rules and converts rule failures into a risk decision.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Errors
  alias BravoCredit.Rules.Engine

  @impl true
  def call(%{application: application, country_config: country_config} = context) do
    input = %{
      amount: application.amount,
      monthly_income: application.monthly_income
    }

    case Engine.evaluate(country_config, :provider, input, application.banking_info) do
      :ok ->
        {:ok, context}

      {:error, %{code: "validation.invalid_params"} = error} ->
        {:error, Errors.provider_invalid_response(error.details)}

      {:error, %{code: code} = error}
      when is_binary(code) and code in ["rules.initial_rejected", "rules.provider_rejected"] ->
        {:ok, %{context | decision: %{outcome: :rejected, reason: error}}}

      {:error, error} ->
        {:error, error}
    end
  end
end
