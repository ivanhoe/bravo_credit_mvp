defmodule BravoCredit.Pipeline.Steps.FetchProviderPayload do
  @moduledoc """
  Calls the configured provider adapter and stores the raw provider payload in the context.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Countries.Registry

  @impl true
  def call(%{application: application, country_config: country_config} = context) do
    with {:ok, provider_module} <- Registry.provider_module(country_config.provider.adapter),
         {:ok, provider_data} <- provider_module.fetch(application.document_id) do
      {:ok, %{context | provider_data: provider_data}}
    end
  end
end
