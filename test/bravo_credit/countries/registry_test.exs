defmodule BravoCredit.Countries.RegistryTest do
  use ExUnit.Case, async: true

  alias BravoCredit.Countries.Registry

  test "loads MX and CO country configs" do
    configs = Registry.all()

    assert Map.keys(configs) |> Enum.sort() == ["CO", "MX"]

    assert %{
             country_name: "Mexico",
             currency: "MXN",
             document: %{type: "CURP", validator_module: BravoCredit.Documents.CURP},
             provider: %{adapter_module: BravoCredit.Banking.Providers.MX},
             state_transitions: %{approved: [:cancelled]}
           } = configs["MX"]

    assert %{
             country_name: "Colombia",
             currency: "COP",
             document: %{type: "CC", validator_module: BravoCredit.Documents.CC},
             provider: %{adapter_module: BravoCredit.Banking.Providers.CO},
             state_transitions: %{approved: [], in_review: [:approved, :rejected]}
           } = configs["CO"]
  end

  test "returns a canonical domain error for unsupported countries" do
    assert {:error, error} = Registry.get("br")

    assert error.code == "country.unsupported"
    assert error.details == %{country_code: "BR"}
  end
end
