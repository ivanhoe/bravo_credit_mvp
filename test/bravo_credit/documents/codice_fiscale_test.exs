defmodule BravoCredit.Documents.CodiceFiscaleTest do
  use ExUnit.Case, async: true

  alias BravoCredit.Documents.CodiceFiscale

  test "accepts a valid codice fiscale shape" do
    assert :ok = CodiceFiscale.validate("RSSMRA85T10A562S")
  end

  test "normalizes casing before validating" do
    assert :ok = CodiceFiscale.validate(" rssmra85t10a562s ")
  end

  test "rejects invalid codice fiscale values" do
    assert {:error, error} = CodiceFiscale.validate("INVALID-CF")
    assert error.code == "document.invalid_format"
  end
end
