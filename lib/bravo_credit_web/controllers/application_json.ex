defmodule BravoCreditWeb.ApplicationJSON do
  @moduledoc """
  JSON rendering helpers for application resources.
  """

  alias BravoCredit.Applications.Application
  alias BravoCredit.Countries.Registry

  def index(%{applications: applications}) do
    %{data: Enum.map(applications, &data/1)}
  end

  def show(%{application: application, detail: true} = assigns) do
    %{data: detail_data(application, Map.get(assigns, :available_transitions, []))}
  end

  def show(%{application: application}) do
    %{data: data(application)}
  end

  defp data(%Application{} = application) do
    %{
      id: application.id,
      country_code: application.country_code,
      status: application.status,
      risk_status: application.risk_status,
      risk_score: application.risk_score,
      amount: application.amount,
      monthly_income: application.monthly_income,
      requested_at: application.requested_at,
      lock_version: application.lock_version
    }
  end

  defp detail_data(%Application{} = application, available_transitions) do
    data(application)
    |> Map.merge(%{
      country_name: country_name(application.country_code),
      full_name: application.full_name,
      document_type: application.document_type,
      document_id_masked: mask_value(application.document_id),
      metadata: application.metadata,
      banking_info: redact_banking_info(application.banking_info),
      available_transitions: available_transitions,
      inserted_at: application.inserted_at,
      updated_at: application.updated_at
    })
  end

  defp country_name(country_code) do
    case Registry.get(country_code) do
      {:ok, country_config} -> country_config.country_name
      {:error, _error} -> country_code
    end
  end

  defp redact_banking_info(banking_info) when is_map(banking_info) do
    banking_info
    |> maybe_mask_key("provider_reference")
    |> maybe_mask_key("account_number")
    |> maybe_mask_key("iban")
    |> maybe_mask_key("clabe")
  end

  defp redact_banking_info(_banking_info), do: %{}

  defp maybe_mask_key(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) -> Map.put(map, key, mask_value(value))
      _value -> map
    end
  end

  defp mask_value(nil), do: nil

  defp mask_value(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      nil
    else
      visible = String.slice(value, -4, 4) || value
      String.duplicate("*", max(String.length(value) - String.length(visible), 0)) <> visible
    end
  end
end
