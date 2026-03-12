defmodule BravoCredit.Pipeline.Steps.CalculateRiskScore do
  @moduledoc """
  Calculates a normalized risk score based on country-specific provider data.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Errors

  @impl true
  def call(%{application: application} = context) do
    with {:ok, risk_score} <- extract_risk_score(application) do
      {:ok, put_in(context.decision, merge_decision(context.decision, %{risk_score: risk_score}))}
    end
  end

  defp extract_risk_score(%{banking_info: banking_info} = application) do
    case Map.get(banking_info, "credit_score") do
      score when is_integer(score) and score >= 0 and score <= 1_000 ->
        {:ok, score}

      _other ->
        extract_ratio_based_risk_score(application)
    end
  end

  defp extract_ratio_based_risk_score(%{
         banking_info: banking_info,
         monthly_income: monthly_income
       }) do
    ratio_input = Map.put(banking_info, "monthly_income", monthly_income)

    with {:ok, total_debt} <- decimal_from(ratio_input, "total_debt"),
         {:ok, normalized_monthly_income} <- decimal_from(ratio_input, "monthly_income"),
         {:ok, ratio} <- safe_divide(total_debt, normalized_monthly_income) do
      score =
        ratio
        |> Decimal.mult(Decimal.new("1000"))
        |> Decimal.round(0)
        |> Decimal.to_integer()
        |> then(&(1_000 - &1))
        |> clamp_score()

      {:ok, score}
    else
      {:error, _reason} ->
        {:error, Errors.provider_invalid_response(%{field: "total_debt"})}
    end
  end

  defp decimal_from(data, key) do
    case Map.get(data, key) do
      nil -> {:error, :missing}
      value -> Decimal.cast(value)
    end
  end

  defp safe_divide(_value, divisor) when is_nil(divisor), do: {:error, :invalid_divisor}

  defp safe_divide(value, divisor) do
    if Decimal.compare(divisor, 0) == :gt do
      {:ok, Decimal.div(value, divisor)}
    else
      {:error, :invalid_divisor}
    end
  end

  defp clamp_score(score) when score < 0, do: 0
  defp clamp_score(score) when score > 1_000, do: 1_000
  defp clamp_score(score), do: score

  defp merge_decision(nil, attrs), do: attrs
  defp merge_decision(decision, attrs), do: Map.merge(decision, attrs)
end
