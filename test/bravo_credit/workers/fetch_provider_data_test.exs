defmodule BravoCredit.Workers.FetchProviderDataTest do
  use BravoCredit.DataCase, async: false

  import Ecto.Query
  import Mox

  alias BravoCredit.Applications
  alias BravoCredit.Applications.Application, as: CreditApplication
  alias BravoCredit.Applications.ApplicationEvent
  alias BravoCredit.Outbox.Event, as: OutboxEvent
  alias BravoCredit.Workers.FetchProviderData
  alias Oban.Job

  setup :verify_on_exit!

  setup do
    previous_registry = Elixir.Application.get_env(:bravo_credit, :country_provider_registry)

    Elixir.Application.put_env(:bravo_credit, :country_provider_registry, %{
      "bank_mx" => BravoCredit.Banking.ProviderMock,
      "bank_co" => BravoCredit.Banking.Providers.CO
    })

    on_exit(fn ->
      if previous_registry do
        Elixir.Application.put_env(:bravo_credit, :country_provider_registry, previous_registry)
      else
        Elixir.Application.delete_env(:bravo_credit, :country_provider_registry)
      end
    end)

    :ok
  end

  test "fetches, sanitizes, and persists provider data while enqueueing risk evaluation" do
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

    BravoCredit.Banking.ProviderMock
    |> expect(:fetch, fn "GODE561231HDFRRN04" ->
      {:ok,
       %{
         provider_reference: "mx-rrn04",
         credit_score: 710,
         total_debt: Decimal.new("18000.00"),
         ignored_field: "should_not_persist"
       }}
    end)

    assert :ok =
             FetchProviderData.perform(%Job{
               args: %{
                 "application_id" => application.id,
                 "country_code" => application.country_code,
                 "request_id" => Ecto.UUID.generate()
               }
             })

    updated_application = Repo.get!(CreditApplication, application.id)

    assert updated_application.status == :evaluating
    assert updated_application.risk_status == :provider_data_ready
    assert updated_application.banking_info["provider"] == "bank_mx"
    assert updated_application.banking_info["credit_score"] == 710
    assert updated_application.banking_info["total_debt"] == "18000.00"
    refute Map.has_key?(updated_application.banking_info, "ignored_field")

    assert Repo.exists?(
             from event in ApplicationEvent,
               where:
                 event.application_id == ^application.id and
                   event.event_type == "application.provider_data_received"
           )

    assert Repo.exists?(
             from event in OutboxEvent,
               where:
                 event.aggregate_id == ^application.id and
                   event.event_type == "application.provider_data_received"
           )

    evaluate_risk_jobs =
      from(job in Job, where: job.worker == "BravoCredit.Workers.EvaluateRisk")
      |> Repo.all()

    assert length(evaluate_risk_jobs) == 1
    assert hd(evaluate_risk_jobs).args["application_id"] == application.id
  end
end
