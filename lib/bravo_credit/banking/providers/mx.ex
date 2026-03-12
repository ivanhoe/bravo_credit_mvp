defmodule BravoCredit.Banking.Providers.MX do
  @moduledoc """
  Simulated MX banking provider.
  """

  @behaviour BravoCredit.Banking.Provider

  @impl true
  def fetch(document_id) do
    suffix = document_id |> String.trim() |> String.slice(-4, 4)

    {:ok,
     %{
       provider_reference: "mx-#{suffix}",
       credit_score: 720,
       total_debt: Decimal.new("15000.00")
     }}
  end
end
