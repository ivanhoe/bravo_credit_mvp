defmodule BravoCredit.Banking.Providers.IT do
  @moduledoc """
  Simulated IT banking provider.
  """

  @behaviour BravoCredit.Banking.Provider

  @impl true
  def fetch(document_id) do
    suffix = document_id |> String.trim() |> String.slice(-4, 4)

    {:ok,
     %{
       provider_reference: "it-#{suffix}",
       credit_score: 705,
       total_debt: Decimal.new("9500.00"),
       income_stability: "stable"
     }}
  end
end
