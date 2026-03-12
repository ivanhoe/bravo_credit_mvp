defmodule BravoCredit.Workers.EvaluateRisk do
  @moduledoc """
  Placeholder worker for the next phase's risk evaluation flow.
  """

  use Oban.Worker, queue: :risk, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"application_id" => _application_id}}), do: :ok
end
