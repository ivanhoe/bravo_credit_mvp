defmodule BravoCredit.Encrypted.Map do
  @moduledoc """
  Cloak-backed map field for encrypted JSON-like payloads.
  """

  use Cloak.Ecto.Map, vault: BravoCredit.Vault
end
