defmodule BravoCreditWeb.HealthControllerTest do
  use BravoCreditWeb.ConnCase, async: true

  test "GET /health returns ok", %{conn: conn} do
    response =
      conn
      |> get(~p"/health")
      |> json_response(200)

    assert response == %{"status" => "ok"}
  end
end
