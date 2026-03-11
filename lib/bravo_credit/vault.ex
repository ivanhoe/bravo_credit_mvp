defmodule BravoCredit.Vault do
  @moduledoc """
  Cloak vault used to encrypt PII at rest.
  """

  use Cloak.Vault, otp_app: :bravo_credit
end
