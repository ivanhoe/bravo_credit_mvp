defmodule BravoCredit.Pipelines.UpdateApplicationStateTest do
  use BravoCredit.DataCase, async: true

  alias BravoCredit.Accounts.User
  alias BravoCredit.Applications
  alias BravoCredit.Applications.Application, as: CreditApplication
  alias BravoCredit.Pipelines.UpdateApplicationState

  test "allows an analyst to approve an in_review application in an allowed country" do
    user = user_fixture(role: :analyst, country_access: ["MX"])
    application = application_fixture("MX", :in_review, :manual_review)

    assert {:ok, context} =
             UpdateApplicationState.call(application.id, %{"state" => "approved"}, user)

    assert context.application.status == :approved
    assert context.application.risk_status == :approved
  end

  test "rejects transitions that are not valid from the current status" do
    user = user_fixture(role: :admin, country_access: ["MX"])
    application = application_fixture("MX", :approved, :approved)

    assert {:error, error} =
             UpdateApplicationState.call(application.id, %{"state" => "pending"}, user)

    assert error.code == "state.invalid_transition"
  end

  test "rejects users without country access" do
    user = user_fixture(role: :analyst, country_access: ["CO"])
    application = application_fixture("MX", :in_review, :manual_review)

    assert {:error, error} =
             UpdateApplicationState.call(application.id, %{"state" => "approved"}, user)

    assert error.code == "auth.forbidden_country"
  end

  test "enforces country-specific transition policies" do
    user = user_fixture(role: :admin, country_access: ["CO"])
    application = application_fixture("CO", :approved, :approved)

    assert {:error, error} =
             UpdateApplicationState.call(application.id, %{"state" => "cancelled"}, user)

    assert error.code == "state.invalid_transition"
  end

  defp user_fixture(attrs) do
    %User{}
    |> User.changeset(
      %{
        email: "ops-#{System.unique_integer([:positive])}@example.com",
        password_hash: String.duplicate("x", 60),
        role: :viewer,
        country_access: []
      }
      |> Map.merge(Map.new(attrs))
    )
    |> Repo.insert!()
  end

  defp application_fixture(country_code, status, risk_status) do
    {:ok, application} =
      Applications.create(
        %{
          "country_code" => country_code,
          "full_name" => "Jane Doe",
          "document_id" => document_id_for(country_code),
          "amount" => "50000.00",
          "monthly_income" => default_monthly_income(country_code)
        },
        "public_api"
      )

    application
    |> CreditApplication.update_changeset(%{
      banking_info: %{"provider" => "bank_#{String.downcase(country_code)}"},
      status: status,
      risk_status: risk_status
    })
    |> Repo.update!()
  end

  defp document_id_for("MX"), do: "GODE561231HDFRRN04"
  defp document_id_for("CO"), do: "1234567890"
  defp default_monthly_income("MX"), do: "25000.00"
  defp default_monthly_income("CO"), do: "1500000.00"
end
