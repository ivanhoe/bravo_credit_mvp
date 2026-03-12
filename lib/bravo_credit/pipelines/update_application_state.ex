defmodule BravoCredit.Pipelines.UpdateApplicationState do
  @moduledoc """
  Manual state transition pipeline with resource authorization and transition validation.
  """

  alias BravoCredit.Accounts.User
  alias BravoCredit.Errors
  alias BravoCredit.Pipeline.Context
  alias BravoCredit.Pipeline.Runner
  alias BravoCredit.Pipeline.Steps

  @steps [
    Steps.LoadApplication,
    Steps.CheckPermissions,
    Steps.ValidateTransition,
    Steps.PersistTransition
  ]

  @spec call(Ecto.UUID.t(), map(), User.t()) ::
          {:ok, Context.t()} | {:error, BravoCredit.Error.t()}
  def call(application_id, params, %User{} = user)
      when is_binary(application_id) and is_map(params) do
    %Context{
      request_id: Ecto.UUID.generate(),
      actor: user,
      raw_params: Map.put(params, "application_id", application_id)
    }
    |> Runner.run(@steps)
  end

  def call(_application_id, _params, _user) do
    {:error, Errors.invalid_params(%{fields: %{application_id: ["is invalid"]}})}
  end
end
