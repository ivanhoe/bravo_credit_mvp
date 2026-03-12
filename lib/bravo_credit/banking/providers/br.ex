defmodule BravoCredit.Banking.Providers.BR do
  @moduledoc """
  Simulated BR banking provider.
  """

  @behaviour BravoCredit.Banking.Provider

  @impl true
  def fetch(document_id) do
    suffix = document_id |> String.trim() |> String.slice(-4, 4)

    {:ok,
     %{
       provider_reference: "br-#{suffix}",
       credit_score: 655,
       total_debt: Decimal.new("2200.00"),
       income_stability: "steady"
     }}
  end
end
