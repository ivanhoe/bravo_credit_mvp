defmodule BravoCredit.Pipeline.Steps.ResolveCountryConfig do
  @moduledoc """
  Resolves the normalized country configuration for the input country code.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Countries.Registry

  @impl true
  def call(%{input: %{country_code: country_code}} = context) do
    case Registry.get(country_code) do
      {:ok, country_config} -> {:ok, %{context | country_config: country_config}}
      {:error, error} -> {:error, error}
    end
  end
end
