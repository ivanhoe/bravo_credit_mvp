defmodule BravoCreditWeb.WebhookControllerTest do
  use BravoCreditWeb.ConnCase, async: true

  alias BravoCredit.Applications.Application, as: CreditApplication
  alias BravoCredit.Repo
  alias BravoCredit.Webhooks.WebhookEvent

  test "POST /api/webhooks/provider accepts a provider webhook", %{conn: conn} do
    application = application_fixture(:evaluating, :provider_data_ready)

    response =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-idempotency-key", "evt-webhook-controller")
      |> post(
        ~p"/api/webhooks/provider",
        Jason.encode!(%{
          application_id: application.id,
          event_type: "provider.application_rejected",
          reason: "provider declined the application"
        })
      )
      |> json_response(202)

    assert %{
             "data" => %{
               "source" => "provider",
               "event_type" => "provider.application_rejected",
               "status" => "received"
             }
           } = response

    assert Repo.aggregate(WebhookEvent, :count) == 1
  end

  test "POST /api/webhooks/provider returns the canonical duplicate error envelope", %{conn: conn} do
    application = application_fixture(:evaluating, :provider_data_ready)

    payload = %{
      application_id: application.id,
      event_type: "provider.application_rejected"
    }

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-idempotency-key", "evt-webhook-duplicate")

    _response =
      conn
      |> post(~p"/api/webhooks/provider", Jason.encode!(payload))
      |> json_response(202)

    response =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-idempotency-key", "evt-webhook-duplicate")
      |> post(~p"/api/webhooks/provider", Jason.encode!(payload))
      |> json_response(409)

    assert response["error"]["code"] == "webhook.duplicate_event"
  end

  defp application_fixture(status, risk_status) do
    unique = System.unique_integer([:positive])

    %CreditApplication{}
    |> CreditApplication.changeset(%{
      country_code: "MX",
      full_name: "Jane Doe",
      full_name_hash: Base.encode16(:crypto.hash(:sha256, "name-#{unique}"), case: :lower),
      document_id: "GODE561231HDFRRN04",
      document_hash: Base.encode16(:crypto.hash(:sha256, "doc-#{unique}"), case: :lower),
      document_type: "CURP",
      amount: Decimal.new("50000.00"),
      monthly_income: Decimal.new("25000.00"),
      status: status,
      risk_status: risk_status,
      metadata: %{}
    })
    |> Repo.insert!()
  end
end
