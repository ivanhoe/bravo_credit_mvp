defmodule BravoCredit.Outbox.Registry do
  @moduledoc """
  Resolves outbox handlers by aggregate type.
  """

  alias BravoCredit.Errors

  @default_registry %{
    "application_event" => BravoCredit.Outbox.Handlers.ApplicationEventProjection
  }

  @spec handler_for(String.t()) :: {:ok, module()} | {:error, BravoCredit.Error.t()}
  def handler_for(aggregate_type) when is_binary(aggregate_type) do
    registry = Application.get_env(:bravo_credit, :outbox_handler_registry, @default_registry)

    case Map.fetch(registry, aggregate_type) do
      {:ok, handler} -> {:ok, handler}
      :error -> {:error, Errors.outbox_dispatch_failed(%{aggregate_type: aggregate_type})}
    end
  end
end
