defmodule BravoCredit.Countries.RegistryTest do
  use ExUnit.Case, async: true

  alias BravoCredit.Countries.Registry

  test "loads all configured country configs" do
    configs = Registry.all()

    assert Map.keys(configs) |> Enum.sort() == ["BR", "CO", "ES", "IT", "MX", "PT"]

    assert %{
             country_name: "Brazil",
             currency: "BRL",
             document: %{type: "CPF", validator_module: BravoCredit.Documents.CPF},
             provider: %{adapter_module: BravoCredit.Banking.Providers.BR},
             state_transitions: %{approved: [:cancelled]}
           } = configs["BR"]

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

    assert %{
             country_name: "Spain",
             currency: "EUR",
             document: %{type: "DNI", validator_module: BravoCredit.Documents.DNI},
             provider: %{adapter_module: BravoCredit.Banking.Providers.ES}
           } = configs["ES"]

    assert %{
             country_name: "Italy",
             currency: "EUR",
             document: %{
               type: "CODICE_FISCALE",
               validator_module: BravoCredit.Documents.CodiceFiscale
             },
             provider: %{adapter_module: BravoCredit.Banking.Providers.IT}
           } = configs["IT"]

    assert %{
             country_name: "Portugal",
             currency: "EUR",
             document: %{type: "NIF", validator_module: BravoCredit.Documents.NIF},
             provider: %{adapter_module: BravoCredit.Banking.Providers.PT}
           } = configs["PT"]
  end

  test "returns a canonical domain error for unsupported countries" do
    assert {:error, error} = Registry.get("cl")

    assert error.code == "country.unsupported"
    assert error.details == %{country_code: "CL"}
  end
end
