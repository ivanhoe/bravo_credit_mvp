defmodule BravoCredit.Countries.ValidatorTest do
  use ExUnit.Case, async: true

  alias BravoCredit.Countries.Validator

  @validator_registry %{
    "curp" => BravoCredit.Documents.CURP,
    "cc_basic" => BravoCredit.Documents.CC,
    "dni" => BravoCredit.Documents.DNI,
    "nif" => BravoCredit.Documents.NIF,
    "codice_fiscale" => BravoCredit.Documents.CodiceFiscale,
    "cpf" => BravoCredit.Documents.CPF
  }
  @provider_registry %{
    "bank_mx" => BravoCredit.Banking.Providers.MX,
    "bank_co" => BravoCredit.Banking.Providers.CO,
    "bank_es" => BravoCredit.Banking.Providers.ES,
    "bank_pt" => BravoCredit.Banking.Providers.PT,
    "bank_it" => BravoCredit.Banking.Providers.IT,
    "bank_br" => BravoCredit.Banking.Providers.BR
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
      "provider" => %{"adapter" => "bank_mx", "timeout_ms" => 5000},
      "state_transitions" => %{
        "approved" => [],
        "in_review" => ["approved", "rejected"]
      }
    }

    assert {:ok, config} = Validator.validate(raw_config, @validator_registry, @provider_registry)
    assert config.country_code == "MX"
    assert config.currency == "MXN"
    assert config.document.validator_module == BravoCredit.Documents.CURP
    assert config.provider.adapter_module == BravoCredit.Banking.Providers.MX
    assert [%{kind: :max_amount_to_income_ratio, threshold: %Decimal{}}] = config.rules
    assert config.state_transitions == %{approved: [], in_review: [:approved, :rejected]}
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

  test "rejects unsupported states in transition policies" do
    raw_config = %{
      "country_code" => "CO",
      "country_name" => "Colombia",
      "currency" => "COP",
      "document" => %{"type" => "CC", "validator" => "cc_basic"},
      "rules" => [],
      "provider" => %{"adapter" => "bank_co", "timeout_ms" => 8000},
      "state_transitions" => %{
        "approved" => ["archived"]
      }
    }

    assert {:error, "state_transitions.approved contains unsupported state: \"archived\""} =
             Validator.validate(raw_config, @validator_registry, @provider_registry)
  end

  test "normalizes European and Brazilian validators and providers" do
    raw_config = %{
      "country_code" => "es",
      "country_name" => "Spain",
      "currency" => "eur",
      "document" => %{"type" => "dni", "validator" => "dni"},
      "rules" => [],
      "provider" => %{"adapter" => "bank_es", "timeout_ms" => 6000},
      "review" => %{"high_amount_threshold" => "30000.00"}
    }

    assert {:ok, config} = Validator.validate(raw_config, @validator_registry, @provider_registry)
    assert config.country_code == "ES"
    assert config.currency == "EUR"
    assert config.document.validator_module == BravoCredit.Documents.DNI
    assert config.provider.adapter_module == BravoCredit.Banking.Providers.ES
    assert config.review == %{"high_amount_threshold" => "30000.00"}
  end
end
