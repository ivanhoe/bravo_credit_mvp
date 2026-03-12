defmodule BravoCredit.Pipeline.Step do
  @moduledoc """
  Behaviour implemented by every pipeline step.
  """

  alias BravoCredit.Error
  alias BravoCredit.Pipeline.Context

  @callback call(Context.t()) :: {:ok, Context.t()} | {:error, Error.t()}
end
