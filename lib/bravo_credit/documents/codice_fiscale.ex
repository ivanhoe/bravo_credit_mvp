defmodule BravoCredit.Documents.CodiceFiscale do
  @moduledoc """
  Basic Italian Codice Fiscale validator.
  """

  @behaviour BravoCredit.Documents.Validator

  alias BravoCredit.Error
  alias BravoCredit.Errors

  @codice_fiscale_regex ~r/^[A-Z]{6}\d{2}[A-EHLMPR-T]\d{2}[A-Z]\d{3}[A-Z]$/

  @impl true
  def validate(document_id) when is_binary(document_id) do
    normalized_document_id = document_id |> String.trim() |> String.upcase()

    if Regex.match?(@codice_fiscale_regex, normalized_document_id) do
      :ok
    else
      {:error, Errors.invalid_document_format("document_id") |> put_reason("invalid_format_it")}
    end
  end

  defp put_reason(%Error{} = error, reason) do
    %{error | details: Map.put(error.details, :reason, reason)}
  end
end
