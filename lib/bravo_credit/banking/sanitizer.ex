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
     %{
       "provider" => adapter,
       "provider_reference" =>
         Map.get(raw_payload, :provider_reference) || Map.get(raw_payload, "provider_reference"),
       "credit_score" =>
         Map.get(raw_payload, :credit_score) || Map.get(raw_payload, "credit_score"),
       "total_debt" =>
         decimal_to_string(
           Map.get(raw_payload, :total_debt) || Map.get(raw_payload, "total_debt")
         ),
       "fetched_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
     }}
  end

  def sanitize(%CountryConfig{country_code: "CO", provider: %{adapter: adapter}}, raw_payload)
      when is_map(raw_payload) do
    {:ok,
     %{
       "provider" => adapter,
       "provider_reference" =>
         Map.get(raw_payload, :provider_reference) || Map.get(raw_payload, "provider_reference"),
       "credit_history" =>
         Map.get(raw_payload, :credit_history) || Map.get(raw_payload, "credit_history"),
       "total_debt" =>
         decimal_to_string(
           Map.get(raw_payload, :total_debt) || Map.get(raw_payload, "total_debt")
         ),
       "fetched_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
     }}
  end

  def sanitize(%CountryConfig{country_code: country_code}, _raw_payload) do
    {:error,
     Errors.internal_error("No sanitizer configured for country", %{country_code: country_code})}
  end

  defp decimal_to_string(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp decimal_to_string(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp decimal_to_string(value) when is_binary(value), do: value
  defp decimal_to_string(nil), do: nil
end
