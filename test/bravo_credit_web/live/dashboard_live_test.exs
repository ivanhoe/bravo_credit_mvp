defmodule BravoCreditWeb.DashboardLiveTest do
  use BravoCreditWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BravoCredit.Applications

  test "renders recent applications on the dashboard", %{conn: conn} do
    {:ok, application} =
      Applications.create(%{
        "country_code" => "MX",
        "full_name" => "Jane Dashboard",
        "document_id" => unique_mx_document_id(),
        "amount" => "50000.00",
        "monthly_income" => "25000.00"
      })

    {:ok, _view, html} = live(conn, ~p"/operations")

    assert html =~ "Operations Console"
    assert html =~ application.id
    assert html =~ "Applications"
  end

  defp unique_mx_document_id do
    suffix =
      System.unique_integer([:positive])
      |> rem(100)
      |> Integer.to_string()
      |> String.pad_leading(2, "0")

    "GODE561231HDFRRN" <> suffix
  end
end
