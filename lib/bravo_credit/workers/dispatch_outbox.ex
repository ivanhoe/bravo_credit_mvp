defmodule BravoCredit.Workers.DispatchOutbox do
  @moduledoc """
  Drains persisted outbox rows produced by PostgreSQL triggers and dispatches non-critical side effects.
  """

  use Oban.Worker, queue: :outbox, max_attempts: 1

  alias BravoCredit.Monitoring.Broadcaster
  alias BravoCredit.Outbox
  alias BravoCredit.Outbox.Registry

  @batch_size 50

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Outbox.list_due_events(limit: @batch_size)
    |> Enum.each(&dispatch_event/1)

    :ok
  end

  defp dispatch_event(event) do
    case Outbox.mark_processing(event) do
      {:ok, processing_event} -> dispatch_processing_event(processing_event)
      {:error, %Ecto.Changeset{}} -> :ok
    end
  end

  defp dispatch_processing_event(processing_event) do
    with {:ok, handler} <- Registry.handler_for(processing_event.aggregate_type),
         :ok <- handler.handle(processing_event),
         {:ok, processed_event} <- Outbox.mark_processed(processing_event) do
      :ok = Broadcaster.broadcast_outbox_event(processed_event)
      :ok
    else
      {:error, %BravoCredit.Error{} = error} ->
        case Outbox.record_failure(processing_event, error) do
          {:ok, failed_event} -> :ok = Broadcaster.broadcast_outbox_event(failed_event)
          {:error, _changeset} -> :ok
        end

        :ok

      {:error, %Ecto.Changeset{}} ->
        :ok
    end
  end
end
