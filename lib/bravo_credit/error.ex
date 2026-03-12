defmodule BravoCredit.Error do
  @moduledoc """
  Structured error used across commands, pipelines, workers, and API boundaries.
  """

  @enforce_keys [:code, :message]
  defstruct [:code, :message, :http_status, :source, :step, :retryable?, details: %{}]

  @type t :: %__MODULE__{
          code: String.t(),
          message: String.t(),
          http_status: pos_integer() | nil,
          source: atom() | nil,
          step: atom() | String.t() | nil,
          retryable?: boolean() | nil,
          details: map()
        }
end
