defmodule BravoCredit.Countries.Rule do
  @moduledoc """
  Normalized business rule loaded from YAML country configuration.
  """

  @enforce_keys [:id, :kind, :evaluation_phase, :message]
  defstruct [:id, :kind, :evaluation_phase, :message, :threshold, :amount, metadata: %{}]

  @type kind :: :max_amount_to_income_ratio | :min_income | :max_total_debt_to_income_ratio
  @type evaluation_phase :: :initial | :provider

  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          evaluation_phase: evaluation_phase(),
          message: String.t(),
          threshold: Decimal.t() | nil,
          amount: Decimal.t() | nil,
          metadata: map()
        }
end
