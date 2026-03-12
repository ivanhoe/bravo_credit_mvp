defmodule BravoCredit.Pipeline.Steps.BuildApplicationChangeset do
  @moduledoc """
  Builds the application changeset that will be persisted transactionally.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Applications.Application

  @impl true
  def call(%{input: input, country_config: country_config, request_id: request_id} = context) do
    attrs = %{
      country_code: input.country_code,
      full_name: input.full_name,
      full_name_hash: hash(normalize_name(input.full_name)),
      document_id: normalize_document_id(country_config.document.type, input.document_id),
      document_hash: hash(normalize_document_id(country_config.document.type, input.document_id)),
      document_type: country_config.document.type,
      amount: input.amount,
      monthly_income: input.monthly_income,
      status: :pending,
      risk_status: :not_started,
      metadata: Map.put(input.metadata, "request_id", request_id)
    }

    changeset = Application.changeset(%Application{}, attrs)

    {:ok, %{context | application_changeset: changeset}}
  end

  defp normalize_name(full_name) do
    full_name
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_document_id("CURP", document_id) do
    document_id
    |> String.trim()
    |> String.upcase()
  end

  defp normalize_document_id("CC", document_id) do
    document_id
    |> String.trim()
    |> String.replace(~r/\s+/, "")
  end

  defp normalize_document_id(_document_type, document_id), do: String.trim(document_id)

  defp hash(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
  end
end
