defmodule BravoCredit.Banking.Providers.ES do
  @moduledoc """
  Simulated ES banking provider.
  """

  @behaviour BravoCredit.Banking.Provider

  @impl true
  def fetch(document_id) do
    suffix = document_id |> String.trim() |> String.slice(-4, 4)

    {:ok,
     %{
       provider_reference: "es-#{suffix}",
       credit_score: 690,
       total_debt: Decimal.new("12000.00"),
       income_stability: "stable"
     }}
  end
end
