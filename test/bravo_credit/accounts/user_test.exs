defmodule BravoCredit.Accounts.UserTest do
  use BravoCredit.DataCase, async: true

  alias BravoCredit.Accounts.User

  test "changeset normalizes email and country access" do
    changeset =
      User.changeset(%User{}, %{
        email: "  ANALYST@Example.COM ",
        password_hash: String.duplicate("x", 60),
        role: :analyst,
        country_access: ["mx", " co ", "MX"]
      })

    assert changeset.valid?
    assert get_change(changeset, :email) == "analyst@example.com"
    assert get_change(changeset, :country_access) == ["MX", "CO"]
  end

  test "changeset validates malformed emails and country codes" do
    changeset =
      User.changeset(%User{}, %{
        email: "invalid email",
        password_hash: "too-short",
        role: :viewer,
        country_access: ["mex"]
      })

    refute changeset.valid?
    assert "must have the @ sign and no spaces" in errors_on(changeset).email
    assert "must contain ISO 3166-1 alpha-2 country codes" in errors_on(changeset).country_access
  end
end
