defmodule BravoCredit.Documents.CPFTest do
  use ExUnit.Case, async: true

  alias BravoCredit.Documents.CPF

  test "accepts a valid CPF" do
    assert :ok = CPF.validate("52998224725")
  end

  test "removes punctuation before validating" do
    assert :ok = CPF.validate("529.982.247-25")
  end

  test "rejects invalid CPF values" do
    assert {:error, error} = CPF.validate("11111111111")
    assert error.code == "document.invalid_format"
  end
end
