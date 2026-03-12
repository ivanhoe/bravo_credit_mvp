defmodule BravoCredit.Banking.Providers.PT do
  @moduledoc """
  Simulated PT banking provider.
  """

  @behaviour BravoCredit.Banking.Provider

  @impl true
  def fetch(document_id) do
    suffix = document_id |> String.trim() |> String.slice(-4, 4)

    {:ok,
     %{
       provider_reference: "pt-#{suffix}",
       credit_score: 675,
       total_debt: Decimal.new("7000.00"),
       income_stability: "stable"
     }}
  end
end
