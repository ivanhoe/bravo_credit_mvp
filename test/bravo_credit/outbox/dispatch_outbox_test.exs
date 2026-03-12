defmodule BravoCredit.Outbox.DispatchOutboxTest do
  use BravoCredit.DataCase, async: false

  import Mox

  alias BravoCredit.Applications.Application, as: CreditApplication
  alias BravoCredit.Applications.ApplicationEvent
  alias BravoCredit.Outbox.Event
  alias BravoCredit.Workers.DispatchOutbox
  alias Oban.Job

  setup :verify_on_exit!

  setup do
    previous_registry = Elixir.Application.get_env(:bravo_credit, :outbox_handler_registry)

    Elixir.Application.put_env(:bravo_credit, :outbox_handler_registry, %{
      "application_event" => BravoCredit.Outbox.HandlerMock
    })

    on_exit(fn ->
      if previous_registry do
        Elixir.Application.put_env(:bravo_credit, :outbox_handler_registry, previous_registry)
      else
        Elixir.Application.delete_env(:bravo_credit, :outbox_handler_registry)
      end
    end)

    :ok
  end

  test "dispatches trigger-created outbox rows and marks them processed" do
    application = application_fixture()

    event =
      %ApplicationEvent{}
      |> ApplicationEvent.changeset(%{
        application_id: application.id,
        event_type: "application.created",
        actor: "system",
        payload: %{"application_id" => application.id}
      })
      |> Repo.insert!()

    outbox_event =
      Repo.get_by!(Event,
        aggregate_type: "application_event",
        aggregate_id: event.id,
        event_type: "application.created"
      )

    BravoCredit.Outbox.HandlerMock
    |> expect(:handle, fn %Event{id: id, aggregate_type: "application_event"} ->
      assert id == outbox_event.id
      :ok
    end)

    assert :ok = DispatchOutbox.perform(%Job{args: %{}})

    processed_event = Repo.get!(Event, outbox_event.id)
    assert processed_event.status == :processed
    assert %DateTime{} = processed_event.processed_at
  end

  test "stores retryable failures on the outbox row" do
    application = application_fixture()

    event =
      %ApplicationEvent{}
      |> ApplicationEvent.changeset(%{
        application_id: application.id,
        event_type: "application.created",
        actor: "system",
        payload: %{"application_id" => application.id}
      })
      |> Repo.insert!()

    outbox_event =
      Repo.get_by!(Event,
        aggregate_type: "application_event",
        aggregate_id: event.id,
        event_type: "application.created"
      )

    BravoCredit.Outbox.HandlerMock
    |> expect(:handle, fn %Event{} ->
      {:error, BravoCredit.Errors.outbox_dispatch_failed(%{side_effect: "audit_projection"})}
    end)

    assert :ok = DispatchOutbox.perform(%Job{args: %{}})

    retried_event = Repo.get!(Event, outbox_event.id)
    assert retried_event.status == :pending
    assert retried_event.attempts == 1
    assert retried_event.last_error_code == "outbox.dispatch_failed"
    assert retried_event.processed_at == nil
  end

  defp application_fixture do
    %CreditApplication{}
    |> CreditApplication.changeset(%{
      country_code: "MX",
      full_name: "Jane Doe",
      full_name_hash: String.duplicate("a", 64),
      document_id: "GODE561231HDFRRN04",
      document_hash: String.duplicate("b", 64),
      document_type: "CURP",
      amount: Decimal.new("50000.00"),
      monthly_income: Decimal.new("25000.00"),
      status: :pending,
      risk_status: :not_started,
      metadata: %{}
    })
    |> Repo.insert!()
  end
end
