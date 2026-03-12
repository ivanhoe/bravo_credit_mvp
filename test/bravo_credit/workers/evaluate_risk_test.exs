defmodule BravoCredit.Workers.EvaluateRiskTest do
  use BravoCredit.DataCase, async: true

  import Ecto.Query

  alias BravoCredit.Applications
  alias BravoCredit.Applications.Application, as: CreditApplication
  alias BravoCredit.Applications.ApplicationEvent
  alias BravoCredit.Outbox.Event, as: OutboxEvent
  alias BravoCredit.Workers.EvaluateRisk
  alias Oban.Job

  test "persists the risk evaluation result and audit events" do
    {:ok, application} =
      Applications.create(
        %{
          "country_code" => "MX",
          "full_name" => "Jane Doe",
          "document_id" => "GODE561231HDFRRN04",
          "amount" => "50000.00",
          "monthly_income" => "25000.00"
        },
        "public_api"
      )

    application
    |> CreditApplication.update_changeset(%{
      banking_info: %{
        "provider" => "bank_mx",
        "provider_reference" => "mx-rrn04",
        "credit_score" => 720,
        "total_debt" => "18000.00"
      },
      status: :evaluating,
      risk_status: :provider_data_ready
    })
    |> Repo.update!()

    assert :ok =
             EvaluateRisk.perform(%Job{
               args: %{
                 "application_id" => application.id,
                 "country_code" => application.country_code,
                 "request_id" => Ecto.UUID.generate()
               }
             })

    updated_application = Repo.get!(CreditApplication, application.id)

    assert updated_application.status == :approved
    assert updated_application.risk_status == :approved
    assert updated_application.risk_score == 720

    assert Repo.exists?(
             from event in ApplicationEvent,
               where:
                 event.application_id == ^application.id and
                   event.event_type == "application.risk_evaluated"
           )

    assert Repo.exists?(
             from event in OutboxEvent,
               where:
                 event.aggregate_id == ^application.id and
                   event.event_type == "application.risk_evaluated"
           )
  end
end
