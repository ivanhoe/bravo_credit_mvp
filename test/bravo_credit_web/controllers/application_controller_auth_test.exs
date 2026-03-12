defmodule BravoCreditWeb.ApplicationControllerAuthTest do
  use BravoCreditWeb.ConnCase, async: true

  alias BravoCredit.Accounts
  alias BravoCredit.Accounts.User
  alias BravoCredit.Applications
  alias BravoCredit.Applications.Application, as: CreditApplication
  alias BravoCredit.Repo

  test "GET /api/applications/:id returns an authorized resource", %{conn: conn} do
    user = user_fixture(role: :viewer, country_access: ["MX"])
    application = application_fixture("MX", :approved, :approved)
    token = issue_token!(user)

    response =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> get(~p"/api/applications/#{application.id}")
      |> json_response(200)

    assert response["data"]["id"] == application.id
    assert response["data"]["country_code"] == "MX"
    assert response["data"]["country_name"] == "Mexico"
    assert response["data"]["full_name"] == "Jane Doe"
    assert response["data"]["document_type"] == "CURP"
    assert response["data"]["document_id_masked"] =~ "RN04"
    refute Map.has_key?(response["data"], "document_id")
    assert response["data"]["available_transitions"] == ["cancelled"]
    assert response["data"]["banking_info"]["provider_reference"] =~ "9876"
    assert response["data"]["banking_info"]["clabe"] =~ "3210"
  end

  test "GET /api/applications filters to authorized countries", %{conn: conn} do
    user = user_fixture(role: :viewer, country_access: ["MX"])
    token = issue_token!(user)

    _mx_application = application_fixture("MX", :approved, :approved)
    _co_application = application_fixture("CO", :approved, :approved)

    response =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> get(~p"/api/applications")
      |> json_response(200)

    assert length(response["data"]) == 1
    assert hd(response["data"])["country_code"] == "MX"
  end

  test "PATCH /api/applications/:id/state updates status for an analyst", %{conn: conn} do
    user = user_fixture(role: :analyst, country_access: ["MX"])
    application = application_fixture("MX", :in_review, :manual_review)
    token = issue_token!(user)

    response =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("content-type", "application/json")
      |> patch(~p"/api/applications/#{application.id}/state", Jason.encode!(%{state: "approved"}))
      |> json_response(200)

    assert response["data"]["status"] == "approved"
    assert response["data"]["risk_status"] == "approved"
  end

  test "PATCH /api/applications/:id/state rejects unauthorized users", %{conn: conn} do
    user = user_fixture(role: :viewer, country_access: ["MX"])
    application = application_fixture("MX", :in_review, :manual_review)
    token = issue_token!(user)

    response =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("content-type", "application/json")
      |> patch(~p"/api/applications/#{application.id}/state", Jason.encode!(%{state: "approved"}))
      |> json_response(403)

    assert response["error"]["code"] == "auth.forbidden_action"
  end

  test "authenticated endpoints require a bearer token", %{conn: conn} do
    response =
      conn
      |> get(~p"/api/applications")
      |> json_response(401)

    assert response["error"]["code"] == "auth.unauthenticated"
  end

  defp user_fixture(attrs) do
    %User{}
    |> User.changeset(
      %{
        email: "auth-#{System.unique_integer([:positive])}@example.com",
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
      banking_info: %{
        "provider" => "bank_#{String.downcase(country_code)}",
        "provider_reference" => "ref-9876",
        "clabe" => "0123456789012343210"
      },
      status: status,
      risk_status: risk_status
    })
    |> Repo.update!()
  end

  defp issue_token!(user) do
    {:ok, token, _claims} = Accounts.issue_token(user)
    token
  end

  defp document_id_for("MX"), do: "GODE561231HDFRRN04"
  defp document_id_for("CO"), do: "1234567890"
  defp default_monthly_income("MX"), do: "25000.00"
  defp default_monthly_income("CO"), do: "1500000.00"
end
