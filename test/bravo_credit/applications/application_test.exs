defmodule BravoCredit.Applications.ApplicationTest do
  use BravoCredit.DataCase, async: true

  alias BravoCredit.Applications.Application

  test "changeset auto-fills requested_at and accepts a valid payload" do
    changeset = Application.changeset(%Application{}, valid_attrs())

    assert changeset.valid?
    assert %DateTime{} = get_field(changeset, :requested_at)
    assert get_change(changeset, :country_code) == "MX"
  end

  test "changeset rejects invalid amounts and country codes" do
    changeset =
      Application.changeset(%Application{}, %{
        valid_attrs()
        | country_code: "mex",
          amount: Decimal.new("-1"),
          monthly_income: Decimal.new("0")
      })

    refute changeset.valid?
    assert "should be 2 character(s)" in errors_on(changeset).country_code
    assert "must be greater than 0" in errors_on(changeset).amount
    assert "must be greater than 0" in errors_on(changeset).monthly_income
  end

  defp valid_attrs do
    %{
      country_code: "mx",
      full_name: "Jane Doe",
      full_name_hash: String.duplicate("a", 64),
      document_id: "CURP123456HDFABC01",
      document_hash: String.duplicate("b", 64),
      document_type: "CURP",
      amount: Decimal.new("15000.50"),
      monthly_income: Decimal.new("45000.00"),
      status: :pending,
      risk_status: :not_started,
      metadata: %{source: "test"}
    }
  end
end
