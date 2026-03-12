defmodule BravoCredit.Banking.Providers.CO do
  @moduledoc """
  Simulated CO banking provider.
  """

  @behaviour BravoCredit.Banking.Provider

  @impl true
  def fetch(document_id) do
    suffix = document_id |> String.trim() |> String.slice(-4, 4)

    {:ok,
     %{
       provider_reference: "co-#{suffix}",
       total_debt: Decimal.new("320000.00"),
       average_bank_balance: Decimal.new("2100000.00")
     }}
  end
end
