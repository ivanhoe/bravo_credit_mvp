defmodule BravoCredit.Pipeline.Steps.DecideOutcome do
  @moduledoc """
  Applies country-level outcome policy after rules and score calculation.
  """

  @behaviour BravoCredit.Pipeline.Step

  @mx_auto_approval_score 650

  @impl true
  def call(%{application: %{country_code: "MX"}, decision: decision} = context) do
    decision = decision || %{}
    score = Map.fetch!(decision, :risk_score)

    final_decision =
      cond do
        decision[:outcome] == :rejected ->
          decision

        score < @mx_auto_approval_score ->
          decision
          |> Map.put(:outcome, :in_review)
          |> Map.put(:risk_status, :manual_review)
          |> Map.put(:reason, %{
            code: "risk.manual_review",
            message: "Credit score requires manual review",
            details: %{credit_score: score, threshold: @mx_auto_approval_score}
          })

        true ->
          decision
          |> Map.put(:outcome, :approved)
          |> Map.put(:risk_status, :approved)
      end

    {:ok, %{context | decision: ensure_final_risk_status(final_decision)}}
  end

  def call(%{application: %{country_code: "CO"}, decision: decision} = context) do
    final_decision =
      case decision do
        %{outcome: :rejected} = rejected_decision ->
          Map.put_new(rejected_decision, :risk_status, :rejected)

        decision ->
          (decision || %{})
          |> Map.put(:outcome, :approved)
          |> Map.put(:risk_status, :approved)
      end

    {:ok, %{context | decision: final_decision}}
  end

  defp ensure_final_risk_status(%{outcome: :rejected} = decision) do
    Map.put_new(decision, :risk_status, :rejected)
  end

  defp ensure_final_risk_status(decision), do: decision
end
