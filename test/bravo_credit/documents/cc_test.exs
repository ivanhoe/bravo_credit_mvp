defmodule BravoCredit.Documents.CCTest do
  use ExUnit.Case, async: true

  alias BravoCredit.Documents.CC

  test "accepts a valid colombian citizen id" do
    assert :ok = CC.validate("1234567890")
  end

  test "removes whitespace before validating" do
    assert :ok = CC.validate(" 123 456 789 ")
  end

  test "rejects non numeric values" do
    assert {:error, error} = CC.validate("ABC-123")
    assert error.code == "document.invalid_format"
  end
end
