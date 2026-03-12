defmodule BravoCredit.Pipelines.CreateApplicationTest do
  use BravoCredit.DataCase, async: true

  alias BravoCredit.Applications.Application
  alias BravoCredit.Applications.ApplicationEvent
  alias BravoCredit.Outbox.Event, as: OutboxEvent
  alias BravoCredit.Pipelines.CreateApplication
  alias Oban.Job

  test "persists the application, event, outbox entry, and provider job" do
    params = %{
      "country_code" => "MX",
      "full_name" => "Jane Doe",
      "document_id" => "GODE561231HDFRRN04",
      "amount" => "50000.00",
      "monthly_income" => "25000.00",
      "metadata" => %{"channel" => "web"}
    }

    assert {:ok, context} = CreateApplication.call(params, "public_api")

    assert %Application{} = context.application
    assert context.application.country_code == "MX"
    assert context.application.status == :pending
    assert context.application.risk_status == :not_started

    assert Repo.aggregate(Application, :count) == 1
    assert Repo.aggregate(ApplicationEvent, :count) == 1
    assert Repo.aggregate(OutboxEvent, :count) == 1
    assert Repo.aggregate(Job, :count) == 1

    assert [%Job{} = job] = Repo.all(Job)
    assert job.worker == "BravoCredit.Workers.FetchProviderData"
    assert job.args["application_id"] == context.application.id

    assert [%ApplicationEvent{} = event] = Repo.all(ApplicationEvent)
    assert event.event_type == "application.created"
    assert event.actor == "public_api"
  end

  test "returns a structured error and annotates the failing step" do
    params = %{
      "country_code" => "BR",
      "full_name" => "Jane Doe",
      "document_id" => "1234567890",
      "amount" => "50000.00",
      "monthly_income" => "25000.00"
    }

    assert {:error, error} = CreateApplication.call(params, "public_api")
    assert error.code == "country.unsupported"
    assert error.step == :resolve_country_config
  end
end
