defmodule BravoCredit.WebhooksTest do
  use BravoCredit.DataCase, async: true

  alias BravoCredit.Applications.Application, as: CreditApplication
  alias BravoCredit.Webhooks
  alias BravoCredit.Webhooks.WebhookEvent
  alias Oban.Job

  test "receive_provider persists the webhook event and enqueues processing" do
    application = application_fixture(:evaluating, :provider_data_ready)

    params = %{
      "application_id" => application.id,
      "event_type" => "provider.manual_review_requested",
      "idempotency_key" => "evt-manual-review",
      "reason" => "provider requested extra checks"
    }

    assert {:ok, webhook_event} = Webhooks.receive_provider(params)

    assert webhook_event.source == "provider"
    assert webhook_event.status == :received

    persisted_event = Repo.get!(WebhookEvent, webhook_event.id)
    assert persisted_event.payload["application_id"] == application.id
    assert persisted_event.payload["reason"] == "provider requested extra checks"

    assert [%Job{} = job] =
             Repo.all(
               from(job in Job,
                 where: job.worker == "BravoCredit.Workers.ProcessIncomingWebhook",
                 order_by: [desc: job.inserted_at]
               )
             )

    assert job.args["webhook_event_id"] == webhook_event.id
  end

  test "receive_provider returns a structured duplicate error for repeated idempotency keys" do
    application = application_fixture(:evaluating, :provider_data_ready)

    params = %{
      "application_id" => application.id,
      "event_type" => "provider.application_rejected",
      "idempotency_key" => "evt-duplicate"
    }

    assert {:ok, _webhook_event} = Webhooks.receive_provider(params)
    assert {:error, error} = Webhooks.receive_provider(params)

    assert error.code == "webhook.duplicate_event"
    assert error.http_status == 409
  end

  defp application_fixture(status, risk_status) do
    unique = System.unique_integer([:positive])

    %CreditApplication{}
    |> CreditApplication.changeset(%{
      country_code: "MX",
      full_name: "Jane Doe",
      full_name_hash: String.duplicate(Integer.to_string(rem(unique, 10)), 64),
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
