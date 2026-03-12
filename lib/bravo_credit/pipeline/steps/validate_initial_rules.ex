defmodule BravoCredit.Pipeline.Steps.ValidateInitialRules do
  @moduledoc """
  Evaluates the initial, synchronous business rules for the selected country.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Rules.Engine

  @impl true
  def call(%{country_config: country_config, input: input} = context) do
    case Engine.evaluate(country_config, :initial, Map.from_struct(input)) do
      :ok -> {:ok, context}
      {:error, error} -> {:error, error}
    end
  end
end
