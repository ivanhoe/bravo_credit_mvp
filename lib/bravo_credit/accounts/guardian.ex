defmodule BravoCredit.Accounts.Guardian do
  @moduledoc """
  Guardian implementation for JWT authentication.
  """

  use Guardian, otp_app: :bravo_credit

  alias BravoCredit.Accounts

  @impl true
  def subject_for_token(%{id: id}, _claims) when not is_nil(id) do
    {:ok, to_string(id)}
  end

  def subject_for_token(_, _claims), do: {:error, :missing_subject}

  @impl true
  def resource_from_claims(%{"sub" => id}) do
    case Accounts.get_user(id) do
      nil -> {:error, :resource_not_found}
      user -> {:ok, user}
    end
  end

  def resource_from_claims(_claims), do: {:error, :missing_subject}
end
