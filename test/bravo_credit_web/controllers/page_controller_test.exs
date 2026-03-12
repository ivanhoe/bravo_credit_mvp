defmodule BravoCreditWeb.PageControllerTest do
  use BravoCreditWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/operations"
  end
end
