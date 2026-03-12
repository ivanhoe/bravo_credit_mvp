defmodule BravoCredit.Documents.NIFTest do
  use ExUnit.Case, async: true

  alias BravoCredit.Documents.NIF

  test "accepts a valid portuguese NIF" do
    assert :ok = NIF.validate("123456789")
  end

  test "removes whitespace before validating" do
    assert :ok = NIF.validate(" 123 456 789 ")
  end

  test "rejects invalid NIF values" do
    assert {:error, error} = NIF.validate("123456780")
    assert error.code == "document.invalid_format"
  end
end
