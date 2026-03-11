defmodule BravoCredit.Accounts.Guardian do
  @moduledoc """
  Guardian implementation for JWT authentication.
  """

  use Guardian, otp_app: :bravo_credit

  @impl true
  def subject_for_token(%{id: id}, _claims) when not is_nil(id) do
    {:ok, to_string(id)}
  end

  def subject_for_token(_, _claims), do: {:error, :missing_subject}

  @impl true
  def resource_from_claims(%{"sub" => id}) do
    {:ok, %{id: id}}
  end

  def resource_from_claims(_claims), do: {:error, :missing_subject}
end
