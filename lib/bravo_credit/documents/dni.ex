defmodule BravoCredit.Documents.DNI do
  @moduledoc """
  Spanish DNI validator with checksum verification.
  """

  @behaviour BravoCredit.Documents.Validator

  alias BravoCredit.Error
  alias BravoCredit.Errors

  @dni_regex ~r/^\d{8}[A-Z]$/
  @checksum_letters String.graphemes("TRWAGMYFPDXBNJZSQVHLCKE")

  @impl true
  def validate(document_id) when is_binary(document_id) do
    normalized_document_id = document_id |> String.trim() |> String.upcase()

    if Regex.match?(@dni_regex, normalized_document_id) do
      {number, expected_letter} = split_dni(normalized_document_id)

      if checksum_letter(number) == expected_letter do
        :ok
      else
        {:error, Errors.invalid_document_format("document_id") |> put_reason("invalid_checksum")}
      end
    else
      {:error,
       Errors.invalid_document_format("document_id")
       |> put_reason("must_be_8_digits_and_1_letter")}
    end
  end

  defp put_reason(%Error{} = error, reason) do
    %{error | details: Map.put(error.details, :reason, reason)}
  end

  defp split_dni(document_id) do
    {String.slice(document_id, 0, 8), String.slice(document_id, 8, 1)}
  end

  defp checksum_letter(number) do
    number
    |> String.to_integer()
    |> rem(23)
    |> then(&Enum.at(@checksum_letters, &1))
  end
end
