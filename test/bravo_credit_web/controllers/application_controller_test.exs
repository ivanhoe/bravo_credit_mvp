defmodule BravoCreditWeb.ApplicationControllerTest do
  use BravoCreditWeb.ConnCase, async: true

  test "POST /api/applications creates an application" do
    payload = %{
      country_code: "MX",
      full_name: "Jane Doe",
      document_id: "GODE561231HDFRRN04",
      amount: "50000.00",
      monthly_income: "25000.00",
      metadata: %{channel: "web"}
    }

    response =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/applications", Jason.encode!(payload))
      |> json_response(201)

    assert %{
             "data" => %{
               "country_code" => "MX",
               "status" => "pending",
               "risk_status" => "not_started"
             }
           } = response
  end

  test "POST /api/applications returns the canonical error envelope" do
    payload = %{
      country_code: "MX",
      full_name: "Jane Doe",
      document_id: "bad-doc",
      amount: "50000.00",
      monthly_income: "25000.00"
    }

    response =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/applications", Jason.encode!(payload))
      |> json_response(422)

    assert %{
             "error" => %{
               "code" => "document.invalid_format",
               "message" => "Document format is invalid",
               "details" => %{"field" => "document_id"}
             }
           } = response
  end
end
