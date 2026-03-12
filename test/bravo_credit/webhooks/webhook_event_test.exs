defmodule BravoCredit.Webhooks.WebhookEventTest do
  use BravoCredit.DataCase, async: true

  alias BravoCredit.Webhooks.WebhookEvent

  test "changeset accepts a valid webhook payload" do
    changeset =
      WebhookEvent.changeset(%WebhookEvent{}, %{
        source: "provider-x",
        idempotency_key: "evt_123",
        event_type: "provider.status_changed",
        payload: %{status: "approved"}
      })

    assert changeset.valid?
    assert get_field(changeset, :status) == :received
  end

  test "changeset requires idempotency and source" do
    changeset = WebhookEvent.changeset(%WebhookEvent{}, %{event_type: "provider.status_changed"})

    refute changeset.valid?
    assert "can't be blank" in errors_on(changeset).source
    assert "can't be blank" in errors_on(changeset).idempotency_key
  end
end
