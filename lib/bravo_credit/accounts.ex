defmodule BravoCredit.Accounts do
  @moduledoc """
  Public account services used by authentication and authorization boundaries.
  """

  alias BravoCredit.Accounts.Guardian
  alias BravoCredit.Accounts.User
  alias BravoCredit.Repo

  @spec get_user(Ecto.UUID.t()) :: User.t() | nil
  def get_user(user_id), do: Repo.get(User, user_id)

  @spec issue_token(User.t()) :: {:ok, String.t(), map()} | {:error, term()}
  def issue_token(%User{} = user), do: Guardian.encode_and_sign(user)
end
