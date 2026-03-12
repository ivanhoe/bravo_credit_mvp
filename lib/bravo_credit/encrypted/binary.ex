defmodule BravoCredit.Encrypted.Binary do
  @moduledoc """
  Cloak-backed binary field for encrypted string-like PII.
  """

  use Cloak.Ecto.Binary, vault: BravoCredit.Vault
end
