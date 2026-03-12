defmodule BravoCredit.Documents.NIF do
  @moduledoc """
  Portuguese NIF validator with checksum verification.
  """

  @behaviour BravoCredit.Documents.Validator

  alias BravoCredit.Error
  alias BravoCredit.Errors

  @nif_regex ~r/^\d{9}$/
  @allowed_prefixes ~w(1 2 3 5 6 8 9)

  @impl true
  def validate(document_id) when is_binary(document_id) do
    normalized_document_id = document_id |> String.trim() |> String.replace(~r/\s+/, "")

    cond do
      not Regex.match?(@nif_regex, normalized_document_id) ->
        {:error, Errors.invalid_document_format("document_id") |> put_reason("must_be_9_digits")}

      String.first(normalized_document_id) not in @allowed_prefixes ->
        {:error, Errors.invalid_document_format("document_id") |> put_reason("invalid_prefix_pt")}

      not valid_checksum?(normalized_document_id) ->
        {:error, Errors.invalid_document_format("document_id") |> put_reason("invalid_checksum")}

      true ->
        :ok
    end
  end

  defp put_reason(%Error{} = error, reason) do
    %{error | details: Map.put(error.details, :reason, reason)}
  end

  defp valid_checksum?(document_id) do
    digits = document_id |> String.graphemes() |> Enum.map(&String.to_integer/1)

    check_digit = List.last(digits)

    calculated_digit =
      digits
      |> Enum.take(8)
      |> Enum.zip(9..2//-1)
      |> Enum.reduce(0, fn {digit, weight}, acc -> acc + digit * weight end)
      |> rem(11)
      |> then(fn value -> if value < 2, do: 0, else: 11 - value end)

    calculated_digit == check_digit
  end
end
