defmodule BravoCredit.Workers.ProcessIncomingWebhookTest do
  use BravoCredit.DataCase, async: false

  import Ecto.Query

  alias BravoCredit.Applications.Application, as: CreditApplication
  alias BravoCredit.Applications.ApplicationEvent
  alias BravoCredit.Webhooks
  alias BravoCredit.Webhooks.WebhookEvent
  alias BravoCredit.Workers.ProcessIncomingWebhook
  alias Oban.Job

  test "processes a provider webhook and updates the application state" do
    application = application_fixture(:evaluating, :provider_data_ready)

    assert {:ok, webhook_event} =
             Webhooks.receive_provider(%{
               "application_id" => application.id,
               "event_type" => "provider.manual_review_requested",
               "idempotency_key" => "evt-process-success",
               "reason" => "provider requested manual review"
             })

    assert :ok =
             ProcessIncomingWebhook.perform(%Job{
               args: %{
                 "webhook_event_id" => webhook_event.id,
                 "request_id" => Ecto.UUID.generate()
               }
             })

    updated_application = Repo.get!(CreditApplication, application.id)
    processed_event = Repo.get!(WebhookEvent, webhook_event.id)

    assert updated_application.status == :in_review
    assert updated_application.risk_status == :manual_review

    assert updated_application.metadata["last_webhook_event_type"] ==
             "provider.manual_review_requested"

    assert processed_event.status == :processed
    assert processed_event.application_id == application.id

    assert Repo.exists?(
             from event in ApplicationEvent,
               where:
                 event.application_id == ^application.id and
                   event.event_type == "webhook.received"
           )

    assert Repo.exists?(
             from event in ApplicationEvent,
               where:
                 event.application_id == ^application.id and
                   event.event_type == "application.state_changed"
           )
  end

  test "records non-retryable webhook failures on invalid transitions" do
    application = application_fixture(:approved, :approved)

    assert {:ok, webhook_event} =
             Webhooks.receive_provider(%{
               "application_id" => application.id,
               "event_type" => "provider.manual_review_requested",
               "idempotency_key" => "evt-process-invalid-transition"
             })

    assert {:discard, message} =
             ProcessIncomingWebhook.perform(%Job{
               args: %{
                 "webhook_event_id" => webhook_event.id,
                 "request_id" => Ecto.UUID.generate()
               }
             })

    failed_event = Repo.get!(WebhookEvent, webhook_event.id)
    unchanged_application = Repo.get!(CreditApplication, application.id)

    assert message =~ "state.invalid_transition"
    assert failed_event.status == :failed
    assert failed_event.error_code == "state.invalid_transition"
    assert unchanged_application.status == :approved

    refute Repo.exists?(
             from event in ApplicationEvent, where: event.application_id == ^application.id
           )
  end

  defp application_fixture(status, risk_status) do
    unique = System.unique_integer([:positive])

    %CreditApplication{}
    |> CreditApplication.changeset(%{
      country_code: "MX",
      full_name: "Jane Doe",
      full_name_hash: Base.encode16(:crypto.hash(:sha256, "name-#{unique}"), case: :lower),
      document_id: "GODE561231HDFRRN04",
      document_hash: Base.encode16(:crypto.hash(:sha256, "doc-#{unique}"), case: :lower),
      document_type: "CURP",
      amount: Decimal.new("50000.00"),
      monthly_income: Decimal.new("25000.00"),
      status: status,
      risk_status: risk_status,
      metadata: %{}
    })
    |> Repo.insert!()
  end
end
