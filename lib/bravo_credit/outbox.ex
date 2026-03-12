defmodule BravoCredit.Outbox do
  @moduledoc """
  Query and state transition helpers for persisted outbox events.
  """

  import Ecto.Query

  alias BravoCredit.Error
  alias BravoCredit.Outbox.Event
  alias BravoCredit.Repo

  @max_attempts 10

  @spec list_due_events(keyword()) :: [Event.t()]
  def list_due_events(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Event
    |> where([event], event.status == :pending)
    |> maybe_filter_due_time(Keyword.get(opts, :now))
    |> order_by([event], asc: event.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec mark_processing(Event.t()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def mark_processing(%Event{} = event) do
    event
    |> Event.changeset(%{status: :processing})
    |> Repo.update()
  end

  @spec mark_processed(Event.t()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def mark_processed(%Event{} = event) do
    event
    |> Event.changeset(%{
      status: :processed,
      processed_at: DateTime.utc_now(),
      last_error_code: nil,
      last_error_message: nil,
      last_error_details: %{}
    })
    |> Repo.update()
  end

  @spec record_failure(Event.t(), Error.t()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def record_failure(%Event{} = event, %Error{} = error) do
    attempts = event.attempts + 1
    should_retry? = error.retryable? == true and attempts < @max_attempts

    attrs = %{
      attempts: attempts,
      status: if(should_retry?, do: :pending, else: :failed),
      next_attempt_at: next_attempt_at(attempts, should_retry?),
      last_error_code: error.code,
      last_error_message: error.message,
      last_error_details: error.details
    }

    event
    |> Event.changeset(attrs)
    |> Repo.update()
  end

  defp next_attempt_at(_attempts, false), do: DateTime.utc_now()

  defp next_attempt_at(attempts, true) do
    DateTime.add(DateTime.utc_now(), trunc(:math.pow(2, attempts)), :second)
  end

  defp maybe_filter_due_time(query, nil) do
    where(query, [event], event.next_attempt_at <= fragment("timezone('utc', now())"))
  end

  defp maybe_filter_due_time(query, %DateTime{} = now) do
    where(query, [event], event.next_attempt_at <= ^now)
  end
end
