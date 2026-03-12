defmodule BravoCredit.Banking.Provider do
  @moduledoc """
  Behaviour for simulated banking providers used by country configuration.
  """

  alias BravoCredit.Error

  @callback fetch(String.t()) :: {:ok, map()} | {:error, Error.t()}
end
