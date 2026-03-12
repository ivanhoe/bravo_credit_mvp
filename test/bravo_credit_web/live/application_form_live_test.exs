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
      "monthly_income" => "1800000.00",
      "channel" => "operations-live-test"
    }

    render_submit(form(view, "#application-form", application: params))

    [application] = Repo.all(Application)

    assert_redirect(view, ~p"/applications/#{application.id}")
    assert application.country_code == "CO"
  end

  defp unique_co_document_id do
    System.unique_integer([:positive])
    |> rem(9_000_000_000)
    |> Kernel.+(1_000_000_000)
    |> Integer.to_string()
  end
end
