defmodule BravoCredit.Workers.DispatchOutbox do
  @moduledoc """
  Drains persisted outbox rows produced by PostgreSQL triggers and dispatches non-critical side effects.
  """

  use Oban.Worker, queue: :outbox, max_attempts: 1

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
         {:ok, _processed_event} <- Outbox.mark_processed(processing_event) do
      :ok
    else
      {:error, %BravoCredit.Error{} = error} ->
        _ = Outbox.record_failure(processing_event, error)
        :ok

      {:error, %Ecto.Changeset{}} ->
        :ok
    end
  end
end
