defmodule BravoCredit.Pipeline.Steps.DecideOutcome do
  @moduledoc """
  Applies country-level outcome policy after rules and score calculation.
  """

  @behaviour BravoCredit.Pipeline.Step

  @impl true
  def call(
        %{application: application, country_config: country_config, decision: decision} = context
      ) do
    final_decision =
      decision
      |> normalize_decision()
      |> maybe_route_to_manual_review_for_amount(application, country_config.review)
      |> maybe_route_to_manual_review_for_score(country_config.review)
      |> finalize_outcome()

    {:ok, %{context | decision: final_decision}}
  end

  defp normalize_decision(nil), do: %{}
  defp normalize_decision(decision), do: decision

  defp maybe_route_to_manual_review_for_amount(
         %{outcome: :rejected} = decision,
         _application,
         _review_config
       ),
       do: decision

  defp maybe_route_to_manual_review_for_amount(decision, application, review_config) do
    with {:ok, threshold} <- fetch_decimal(review_config, "high_amount_threshold"),
         :gt <- Decimal.compare(application.amount, threshold) do
      decision
      |> Map.put(:outcome, :in_review)
      |> Map.put(:risk_status, :manual_review)
      |> Map.put(:reason, %{
        code: "risk.manual_review",
        message: "Requested amount requires manual review",
        details: %{
          amount: Decimal.to_string(application.amount, :normal),
          threshold: Decimal.to_string(threshold, :normal)
        }
      })
    else
      _other -> decision
    end
  end

  defp maybe_route_to_manual_review_for_score(%{outcome: :rejected} = decision, _review_config),
    do: ensure_final_risk_status(decision)

  defp maybe_route_to_manual_review_for_score(%{outcome: :in_review} = decision, _review_config),
    do: decision

  defp maybe_route_to_manual_review_for_score(decision, review_config) do
    score = Map.fetch!(decision, :risk_score)

    with {:ok, threshold} <- fetch_integer(review_config, "min_auto_approval_score"),
         true <- score < threshold do
      decision
      |> Map.put(:outcome, :in_review)
      |> Map.put(:risk_status, :manual_review)
      |> Map.put(:reason, %{
        code: "risk.manual_review",
        message: "Credit score requires manual review",
        details: %{credit_score: score, threshold: threshold}
      })
    else
      _other -> decision
    end
  end

  defp finalize_outcome(%{outcome: :rejected} = decision), do: ensure_final_risk_status(decision)

  defp finalize_outcome(%{outcome: :in_review} = decision), do: decision

  defp finalize_outcome(decision) do
    decision
    |> Map.put(:outcome, :approved)
    |> Map.put(:risk_status, :approved)
  end

  defp fetch_decimal(review_config, key) when is_map(review_config) do
    case Map.get(review_config, key) || Map.get(review_config, String.to_atom(key)) do
      nil -> :error
      value -> Decimal.cast(value)
    end
  rescue
    ArgumentError -> :error
  end

  defp fetch_integer(review_config, key) when is_map(review_config) do
    case Map.get(review_config, key) || Map.get(review_config, String.to_atom(key)) do
      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {parsed_value, ""} -> {:ok, parsed_value}
          _other -> :error
        end

      _other ->
        :error
    end
  rescue
    ArgumentError -> :error
  end

  defp ensure_final_risk_status(%{outcome: :rejected} = decision) do
    Map.put_new(decision, :risk_status, :rejected)
  end

  defp ensure_final_risk_status(decision), do: decision
end
