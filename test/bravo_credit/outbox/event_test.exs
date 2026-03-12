defmodule BravoCredit.Outbox.EventTest do
  use BravoCredit.DataCase, async: true

  alias BravoCredit.Outbox.Event

  test "changeset auto-fills next_attempt_at for pending events" do
    changeset =
      Event.changeset(%Event{}, %{
        aggregate_type: "application",
        aggregate_id: Ecto.UUID.generate(),
        event_type: "application.created"
      })

    assert changeset.valid?
    assert get_field(changeset, :status) == :pending
    assert %DateTime{} = get_field(changeset, :next_attempt_at)
  end

  test "changeset validates attempts cannot be negative" do
    changeset =
      Event.changeset(%Event{}, %{
        aggregate_type: "application",
        aggregate_id: Ecto.UUID.generate(),
        event_type: "application.created",
        attempts: -1
      })

    refute changeset.valid?
    assert "must be greater than or equal to 0" in errors_on(changeset).attempts
  end
end
