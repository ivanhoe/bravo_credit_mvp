defmodule BravoCredit.Documents.CPF do
  @moduledoc """
  Brazilian CPF validator with checksum verification.
  """

  @behaviour BravoCredit.Documents.Validator

  alias BravoCredit.Error
  alias BravoCredit.Errors

  @cpf_regex ~r/^\d{11}$/

  @impl true
  def validate(document_id) when is_binary(document_id) do
    normalized_document_id = document_id |> String.trim() |> String.replace(~r/\D+/, "")

    cond do
      not Regex.match?(@cpf_regex, normalized_document_id) ->
        {:error, Errors.invalid_document_format("document_id") |> put_reason("must_be_11_digits")}

      repeated_digits?(normalized_document_id) ->
        {:error, Errors.invalid_document_format("document_id") |> put_reason("repeated_digits")}

      not valid_checksum?(normalized_document_id) ->
        {:error, Errors.invalid_document_format("document_id") |> put_reason("invalid_checksum")}

      true ->
        :ok
    end
  end

  defp put_reason(%Error{} = error, reason) do
    %{error | details: Map.put(error.details, :reason, reason)}
  end

  defp repeated_digits?(document_id) do
    document_id
    |> String.graphemes()
    |> Enum.uniq()
    |> length() == 1
  end

  defp valid_checksum?(document_id) do
    digits = document_id |> String.graphemes() |> Enum.map(&String.to_integer/1)

    first_digit =
      digits
      |> Enum.take(9)
      |> checksum_digit(10)

    second_digit =
      digits
      |> Enum.take(9)
      |> Kernel.++([first_digit])
      |> checksum_digit(11)

    Enum.at(digits, 9) == first_digit and Enum.at(digits, 10) == second_digit
  end

  defp checksum_digit(digits, max_weight) do
    digits
    |> Enum.zip(max_weight..2//-1)
    |> Enum.reduce(0, fn {digit, weight}, acc -> acc + digit * weight end)
    |> rem(11)
    |> then(fn value -> if value < 2, do: 0, else: 11 - value end)
  end
end
