defmodule BravoCredit.Workers.FetchProviderData do
  @moduledoc """
  Placeholder worker for provider data retrieval. The execution flow is implemented in the next phase.
  """

  use Oban.Worker, queue: :providers, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"application_id" => _application_id}}), do: :ok
end
