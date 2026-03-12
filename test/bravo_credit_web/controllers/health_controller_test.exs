defmodule BravoCreditWeb.HealthControllerTest do
  use BravoCreditWeb.ConnCase, async: true

  test "GET /health returns ok", %{conn: conn} do
    response =
      conn
      |> get(~p"/health")
      |> json_response(200)

    assert response == %{"status" => "ok"}
  end

  test "GET /health/ready returns component checks", %{conn: conn} do
    response =
      conn
      |> get(~p"/health/ready")
      |> json_response(200)

    assert response["status"] == "ok"

    assert response["checks"] == %{
             "cache" => "ok",
             "database" => "ok",
             "pubsub" => "ok"
           }
  end
end
