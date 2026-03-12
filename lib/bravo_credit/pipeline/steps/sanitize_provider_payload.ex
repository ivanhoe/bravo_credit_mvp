defmodule BravoCredit.Pipeline.Steps.SanitizeProviderPayload do
  @moduledoc """
  Normalizes and sanitizes provider data before it is persisted to the application aggregate.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Banking.Sanitizer

  @impl true
  def call(%{country_config: country_config, provider_data: provider_data} = context) do
    case Sanitizer.sanitize(country_config, provider_data) do
      {:ok, sanitized_provider_data} -> {:ok, %{context | provider_data: sanitized_provider_data}}
      {:error, error} -> {:error, error}
    end
  end
end
