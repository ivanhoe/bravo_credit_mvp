defmodule BravoCredit.Documents.CURPTest do
  use ExUnit.Case, async: true

  alias BravoCredit.Documents.CURP

  test "accepts a valid CURP" do
    assert :ok = CURP.validate("GODE561231HDFRRN04")
  end

  test "normalizes casing and surrounding spaces" do
    assert :ok = CURP.validate("  gode561231hdfrrn04 ")
  end

  test "rejects invalid CURP values" do
    assert {:error, error} = CURP.validate("INVALID-CURP")
    assert error.code == "document.invalid_format"
  end
end
