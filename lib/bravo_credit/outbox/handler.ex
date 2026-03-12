defmodule BravoCredit.Outbox.Handler do
  @moduledoc """
  Behaviour for non-critical side effects dispatched from the persisted outbox.
  """

  alias BravoCredit.Error
  alias BravoCredit.Outbox.Event

  @callback handle(Event.t()) :: :ok | {:error, Error.t()}
end
