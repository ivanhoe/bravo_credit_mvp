defmodule BravoCredit.Documents.Validator do
  @moduledoc """
  Behaviour implemented by document validators referenced from country configuration.
  """

  alias BravoCredit.Error

  @callback validate(String.t()) :: :ok | {:error, Error.t()}
end
