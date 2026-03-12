defmodule BravoCredit.Documents.DNITest do
  use ExUnit.Case, async: true

  alias BravoCredit.Documents.DNI

  test "accepts a valid spanish DNI" do
    assert :ok = DNI.validate("12345678Z")
  end

  test "normalizes casing and surrounding spaces" do
    assert :ok = DNI.validate(" 12345678z ")
  end

  test "rejects invalid DNI values" do
    assert {:error, error} = DNI.validate("12345678A")
    assert error.code == "document.invalid_format"
  end
end
