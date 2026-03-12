defmodule BravoCredit.Pipeline.Steps.LoadApplication do
  @moduledoc """
  Loads an application aggregate for worker-driven pipelines.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Applications
  alias BravoCredit.Countries.Registry
  alias BravoCredit.Errors

  @impl true
  def call(%{raw_params: %{"application_id" => application_id}} = context) do
    with %{} = application <- Applications.get(application_id),
         {:ok, country_config} <- Registry.get(application.country_code) do
      {:ok, %{context | application: application, country_config: country_config}}
    else
      nil -> {:error, Errors.application_not_found(application_id)}
      {:error, error} -> {:error, error}
    end
  end
end
