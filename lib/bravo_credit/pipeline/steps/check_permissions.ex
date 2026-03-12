defmodule BravoCredit.Pipeline.Steps.CheckPermissions do
  @moduledoc """
  Validates that the acting user can modify the loaded application resource.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Accounts.User
  alias BravoCredit.Errors

  @allowed_roles [:admin, :analyst]

  @impl true
  def call(%{actor: %User{} = user, application: application} = context) do
    cond do
      application.country_code not in user.country_access ->
        {:error, Errors.forbidden_country(application.country_code)}

      user.role not in @allowed_roles ->
        {:error, Errors.forbidden_action("update_application_state")}

      true ->
        {:ok, context}
    end
  end
end
