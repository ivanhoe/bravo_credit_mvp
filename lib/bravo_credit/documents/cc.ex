defmodule BravoCredit.Documents.CC do
  @moduledoc """
  Basic Colombian citizen ID validator.
  """

  @behaviour BravoCredit.Documents.Validator

  alias BravoCredit.Error
  alias BravoCredit.Errors

  @cc_regex ~r/^\d{6,10}$/

  @impl true
  def validate(document_id) when is_binary(document_id) do
    normalized_document_id = document_id |> String.trim() |> String.replace(~r/\s+/, "")

    if Regex.match?(@cc_regex, normalized_document_id) do
      :ok
    else
      {:error, Errors.invalid_document_format("document_id") |> put_reason("invalid_format_co")}
    end
  end

  defp put_reason(%Error{} = error, reason) do
    %{error | details: Map.put(error.details, :reason, reason)}
  end
end
