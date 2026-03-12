defmodule BravoCredit.Pipeline.Steps.ValidateDocument do
  @moduledoc """
  Validates the applicant document using the country-specific validator.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Documents

  @impl true
  def call(%{country_config: country_config, input: %{document_id: document_id}} = context) do
    case Documents.validate(country_config, document_id) do
      :ok -> {:ok, context}
      {:error, error} -> {:error, error}
    end
  end
end
