defmodule BravoCredit.Banking.SanitizerTest do
  use ExUnit.Case, async: true

  alias BravoCredit.Banking.Sanitizer
  alias BravoCredit.Countries.Registry

  test "sanitizes MX provider payloads" do
    country_config = Registry.get!("MX")

    assert {:ok, sanitized} =
             Sanitizer.sanitize(country_config, %{
               provider_reference: "mx-1234",
               credit_score: 720,
               total_debt: Decimal.new("15000.00"),
               ignored_field: "secret"
             })

    assert sanitized["provider"] == "bank_mx"
    assert sanitized["provider_reference"] == "mx-1234"
    assert sanitized["credit_score"] == 720
    assert sanitized["total_debt"] == "15000.00"
    assert is_binary(sanitized["fetched_at"])
    refute Map.has_key?(sanitized, "ignored_field")
  end

  test "sanitizes CO provider payloads" do
    country_config = Registry.get!("CO")

    assert {:ok, sanitized} =
             Sanitizer.sanitize(country_config, %{
               provider_reference: "co-4321",
               credit_history: "clean",
               total_debt: Decimal.new("320000.00")
             })

    assert sanitized["provider"] == "bank_co"
    assert sanitized["provider_reference"] == "co-4321"
    assert sanitized["credit_history"] == "clean"
    assert sanitized["total_debt"] == "320000.00"
  end
end
