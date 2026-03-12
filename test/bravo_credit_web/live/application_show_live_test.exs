defmodule BravoCreditWeb.ApplicationShowLiveTest do
  use BravoCreditWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BravoCredit.Applications
  alias BravoCredit.Applications.Application, as: CreditApplication
  alias BravoCredit.Repo

  test "renders the application detail and persists manual transitions", %{conn: conn} do
    application = in_review_application_fixture()

    {:ok, view, html} = live(conn, ~p"/applications/#{application.id}")

    assert html =~ "Detalle de Solicitud"
    assert html =~ application.id
    assert html =~ "Revisión Manual"

    view
    |> element("[data-state-target='approved']")
    |> render_click()

    updated_application = Repo.get!(CreditApplication, application.id)

    assert updated_application.status == :approved
    assert updated_application.risk_status == :approved
    assert render(view) =~ "Solicitud finalizada correctamente."
  end

  defp in_review_application_fixture do
    {:ok, application} =
      Applications.create(%{
        "country_code" => "MX",
        "full_name" => "Jane Detail",
        "document_id" => unique_mx_document_id(),
        "amount" => "50000.00",
        "monthly_income" => "25000.00"
      })

    application
    |> CreditApplication.update_changeset(%{
      status: :in_review,
      risk_status: :manual_review,
      banking_info: %{"provider" => "bank_mx", "credit_score" => 620}
    })
    |> Repo.update!()
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
