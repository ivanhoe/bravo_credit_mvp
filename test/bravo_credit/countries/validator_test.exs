defmodule BravoCredit.Countries.ValidatorTest do
  use ExUnit.Case, async: true

  alias BravoCredit.Countries.Validator

  @validator_registry %{
    "curp" => BravoCredit.Documents.CURP,
    "cc_basic" => BravoCredit.Documents.CC
  }
  @provider_registry %{
    "bank_mx" => BravoCredit.Banking.Providers.MX,
    "bank_co" => BravoCredit.Banking.Providers.CO
  }

  test "normalizes a valid country config" do
    raw_config = %{
      "country_code" => "mx",
      "country_name" => "Mexico",
      "currency" => "mxn",
      "document" => %{"type" => "curp", "validator" => "curp"},
      "rules" => [
        %{
          "id" => "amount_income_ratio",
          "kind" => "max_amount_to_income_ratio",
          "evaluation_phase" => "initial",
          "threshold" => "4.0",
          "message" => "ratio exceeded"
        }
      ],
      "provider" => %{"adapter" => "bank_mx", "timeout_ms" => 5000}
    }

    assert {:ok, config} = Validator.validate(raw_config, @validator_registry, @provider_registry)
    assert config.country_code == "MX"
    assert config.currency == "MXN"
    assert config.document.validator_module == BravoCredit.Documents.CURP
    assert config.provider.adapter_module == BravoCredit.Banking.Providers.MX
    assert [%{kind: :max_amount_to_income_ratio, threshold: %Decimal{}}] = config.rules
  end

  test "rejects unknown validators" do
    raw_config = %{
      "country_code" => "MX",
      "country_name" => "Mexico",
      "currency" => "MXN",
      "document" => %{"type" => "CURP", "validator" => "missing"},
      "rules" => [],
      "provider" => %{"adapter" => "bank_mx", "timeout_ms" => 5000}
    }

    assert {:error, "unknown validator: \"missing\""} =
             Validator.validate(raw_config, @validator_registry, @provider_registry)
  end

  test "rejects duplicate rule ids" do
    raw_config = %{
      "country_code" => "CO",
      "country_name" => "Colombia",
      "currency" => "COP",
      "document" => %{"type" => "CC", "validator" => "cc_basic"},
      "rules" => [
        %{
          "id" => "duplicate",
          "kind" => "min_income",
          "evaluation_phase" => "initial",
          "amount" => "1500000",
          "message" => "income too low"
        },
        %{
          "id" => "duplicate",
          "kind" => "max_total_debt_to_income_ratio",
          "evaluation_phase" => "provider",
          "threshold" => "0.4",
          "message" => "debt too high"
        }
      ],
      "provider" => %{"adapter" => "bank_co", "timeout_ms" => 8000}
    }

    assert {:error, "rule ids must be unique per country"} =
             Validator.validate(raw_config, @validator_registry, @provider_registry)
  end
end
