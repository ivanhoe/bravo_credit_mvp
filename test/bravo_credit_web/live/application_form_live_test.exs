defmodule BravoCreditWeb.ApplicationFormLiveTest do
  use BravoCreditWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BravoCredit.Applications.Application
  alias BravoCredit.Repo

  test "creates an application and redirects to the detail view", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/applications/new")

    params = %{
      "country_code" => "CO",
      "full_name" => "Maria Applicant",
      "document_id" => unique_co_document_id(),
      "amount" => "3500000.00",
      "monthly_income" => "1800000.00"
    }

    render_submit(form(view, "#application-form", application: params))

    [application] = Repo.all(Application)

    assert_redirect(view, ~p"/applications/#{application.id}")
    assert application.country_code == "CO"
  end

  test "validates required fields with schema before creating", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/applications/new")

    invalid_params = %{
      "country_code" => "MX",
      "full_name" => "",
      "document_id" => "",
      "amount" => "",
      "monthly_income" => ""
    }

    html = render_submit(form(view, "#application-form", application: invalid_params))

    assert html =~ "no puede estar vacío"
    assert has_element?(view, "#application-form")
    assert Repo.aggregate(Application, :count, :id) == 0
  end

  defp unique_co_document_id do
    System.unique_integer([:positive])
    |> rem(9_000_000_000)
    |> Kernel.+(1_000_000_000)
    |> Integer.to_string()
  end
end
