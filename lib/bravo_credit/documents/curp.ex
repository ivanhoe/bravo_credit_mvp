defmodule BravoCredit.Documents.CURP do
  @moduledoc """
  Basic CURP validator for Mexico.
  """

  @behaviour BravoCredit.Documents.Validator

  alias BravoCredit.Error
  alias BravoCredit.Errors

  @curp_regex ~r/^[A-Z][AEIOUX][A-Z]{2}\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])[HM](AS|BC|BS|CC|CL|CM|CS|CH|DF|DG|GT|GR|HG|JC|MC|MN|MS|NT|NL|OC|PL|QT|QR|SP|SL|SR|TC|TS|TL|VZ|YN|ZS|NE)[B-DF-HJ-NP-TV-Z]{3}[A-Z\d]\d$/

  @impl true
  def validate(document_id) when is_binary(document_id) do
    normalized_document_id = document_id |> String.trim() |> String.upcase()

    if Regex.match?(@curp_regex, normalized_document_id) do
      :ok
    else
      {:error, Errors.invalid_document_format("document_id") |> put_reason("invalid_format_mx")}
    end
  end

  defp put_reason(%Error{} = error, reason) do
    %{error | details: Map.put(error.details, :reason, reason)}
  end
end
