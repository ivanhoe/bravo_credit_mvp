defmodule BravoCredit.Rules.Engine do
  @moduledoc """
  Evaluates country-specific rules loaded from YAML.
  """

  alias BravoCredit.Countries.CountryConfig
  alias BravoCredit.Countries.Rule
  alias BravoCredit.Errors

  @type phase :: Rule.evaluation_phase()

  @spec evaluate(CountryConfig.t(), phase(), map(), map()) ::
          :ok | {:error, BravoCredit.Error.t()}
  def evaluate(%CountryConfig{} = country_config, phase, input, provider_data \\ %{})
      when phase in [:initial, :provider] and is_map(input) and is_map(provider_data) do
    country_config.rules
    |> Enum.filter(&(&1.evaluation_phase == phase))
    |> Enum.reduce_while(:ok, fn rule, :ok ->
      case evaluate_rule(rule, input, provider_data) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp evaluate_rule(%Rule{kind: :max_amount_to_income_ratio} = rule, input, _provider_data) do
    with {:ok, amount} <- decimal_from(input, :amount),
         {:ok, monthly_income} <- decimal_from(input, :monthly_income),
         {:ok, ratio} <- safe_divide(amount, monthly_income) do
      compare_lte(ratio, rule.threshold, rule)
    end
  end

  defp evaluate_rule(%Rule{kind: :min_income} = rule, input, _provider_data) do
    with {:ok, monthly_income} <- decimal_from(input, :monthly_income) do
      compare_gte(monthly_income, rule.amount, rule)
    end
  end

  defp evaluate_rule(%Rule{kind: :max_total_debt_to_income_ratio} = rule, input, provider_data) do
    with {:ok, total_debt} <- decimal_from(provider_data, :total_debt),
         {:ok, monthly_income} <- decimal_from(input, :monthly_income),
         {:ok, ratio} <- safe_divide(total_debt, monthly_income) do
      compare_lte(ratio, rule.threshold, rule)
    end
  end

  defp decimal_from(data, key) do
    case Map.get(data, key) || Map.get(data, Atom.to_string(key)) do
      nil -> {:error, Errors.invalid_params(%{field: Atom.to_string(key)})}
      value -> cast_decimal(value, key)
    end
  end

  defp cast_decimal(%Decimal{} = value, _key), do: {:ok, value}

  defp cast_decimal(value, key) do
    case Decimal.cast(value) do
      {:ok, decimal} -> {:ok, decimal}
      :error -> {:error, Errors.invalid_params(%{field: Atom.to_string(key)})}
    end
  end

  defp safe_divide(value, divisor) do
    if Decimal.compare(divisor, 0) == :gt do
      {:ok, Decimal.div(value, divisor)}
    else
      {:error, Errors.invalid_params(%{field: "monthly_income"})}
    end
  end

  defp compare_lte(actual, expected, rule) do
    if Decimal.compare(actual, expected) in [:lt, :eq] do
      :ok
    else
      {:error,
       reject_rule(rule, %{
         actual: decimal_to_string(actual),
         expected: decimal_to_string(expected)
       })}
    end
  end

  defp compare_gte(actual, expected, rule) do
    if Decimal.compare(actual, expected) in [:gt, :eq] do
      :ok
    else
      {:error,
       reject_rule(rule, %{
         actual: decimal_to_string(actual),
         expected: decimal_to_string(expected)
       })}
    end
  end

  defp reject_rule(rule, details) do
    Errors.initial_rules_rejected(rule.message, %{
      rule_id: rule.id,
      kind: rule.kind,
      evaluation_phase: rule.evaluation_phase,
      details: details
    })
  end

  defp decimal_to_string(decimal), do: Decimal.to_string(decimal, :normal)
end
