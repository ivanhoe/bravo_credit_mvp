defmodule BravoCredit.Documents do
  @moduledoc """
  Facade for country-aware document validation.
  """

  alias BravoCredit.Countries.CountryConfig

  @spec validate(CountryConfig.t(), String.t()) :: :ok | {:error, BravoCredit.Error.t()}
  def validate(%CountryConfig{document: %{validator_module: validator_module}}, document_id)
      when is_binary(document_id) do
    validator_module.validate(document_id)
  end
end
