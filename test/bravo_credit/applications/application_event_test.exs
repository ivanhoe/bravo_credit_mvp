defmodule BravoCredit.Applications.ApplicationEventTest do
  use BravoCredit.DataCase, async: true

  alias BravoCredit.Applications.ApplicationEvent

  test "changeset uses schema defaults and validates required fields" do
    application_id = Ecto.UUID.generate()

    changeset =
      ApplicationEvent.changeset(%ApplicationEvent{}, %{
        application_id: application_id,
        event_type: "application.created",
        payload: %{status: "pending"}
      })

    assert changeset.valid?
    assert get_field(changeset, :actor) == "system"
  end

  test "changeset requires event_type" do
    changeset =
      ApplicationEvent.changeset(%ApplicationEvent{}, %{
        application_id: Ecto.UUID.generate()
      })

    refute changeset.valid?
    assert "can't be blank" in errors_on(changeset).event_type
  end
end
