defmodule BravoCredit.Banking.Sanitizer do
  @moduledoc """
  Sanitizes provider payloads before persisting them into `banking_info`.
  """

  alias BravoCredit.Countries.CountryConfig
  alias BravoCredit.Errors

  @spec sanitize(CountryConfig.t(), map()) :: {:ok, map()} | {:error, BravoCredit.Error.t()}
  def sanitize(%CountryConfig{country_code: "MX", provider: %{adapter: adapter}}, raw_payload)
      when is_map(raw_payload) do
    {:ok,
     sanitize_with_fields(adapter, raw_payload, [
       {"provider_reference", :string},
       {"credit_score", :integer},
       {"total_debt", :decimal}
     ])}
  end

  def sanitize(%CountryConfig{country_code: "CO", provider: %{adapter: adapter}}, raw_payload)
      when is_map(raw_payload) do
    {:ok,
     sanitize_with_fields(adapter, raw_payload, [
       {"provider_reference", :string},
       {"credit_history", :string},
       {"total_debt", :decimal}
     ])}
  end

  def sanitize(
        %CountryConfig{country_code: country_code, provider: %{adapter: adapter}},
        raw_payload
      )
      when country_code in ["ES", "PT", "IT", "BR"] and is_map(raw_payload) do
    {:ok,
     sanitize_with_fields(adapter, raw_payload, [
       {"provider_reference", :string},
       {"credit_score", :integer},
       {"total_debt", :decimal},
       {"income_stability", :string}
     ])}
  end

  def sanitize(%CountryConfig{country_code: country_code}, _raw_payload) do
    {:error,
     Errors.internal_error("No sanitizer configured for country", %{country_code: country_code})}
  end

  defp sanitize_with_fields(adapter, raw_payload, fields) do
    fields =
      Enum.reduce(fields, %{}, fn {field_name, type}, acc ->
        case typed_value(raw_payload, field_name, type) do
          nil -> acc
          value -> Map.put(acc, field_name, value)
        end
      end)

    Map.merge(fields, %{
      "provider" => adapter,
      "fetched_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    })
  end

  defp typed_value(raw_payload, field_name, :decimal) do
    raw_payload
    |> payload_value(field_name)
    |> decimal_to_string()
  end

  defp typed_value(raw_payload, field_name, :integer) do
    case payload_value(raw_payload, field_name) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {parsed_value, ""} -> parsed_value
          _other -> nil
        end

      _other ->
        nil
    end
  end

  defp typed_value(raw_payload, field_name, :string) do
    case payload_value(raw_payload, field_name) do
      value when is_binary(value) -> value
      _other -> nil
    end
  end

  defp payload_value(raw_payload, field_name) do
    Map.get(raw_payload, String.to_existing_atom(field_name)) || Map.get(raw_payload, field_name)
  rescue
    ArgumentError ->
      Map.get(raw_payload, field_name)
  end

  defp decimal_to_string(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp decimal_to_string(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp decimal_to_string(value) when is_binary(value), do: value
  defp decimal_to_string(nil), do: nil
end
