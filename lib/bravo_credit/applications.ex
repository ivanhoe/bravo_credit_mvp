defmodule BravoCredit.Applications do
  @moduledoc """
  Public application services for managing credit applications.
  """

  alias BravoCredit.Accounts.User
  alias BravoCredit.Applications.Application
  alias BravoCredit.Applications.Queries
  alias BravoCredit.Monitoring.Broadcaster
  alias BravoCredit.Pipelines.CreateApplication
  alias BravoCredit.Pipelines.UpdateApplicationState
  alias BravoCredit.Repo

  @spec create(map(), term()) ::
          {:ok, BravoCredit.Applications.Application.t()} | {:error, BravoCredit.Error.t()}
  def create(params, actor \\ "public_api") when is_map(params) do
    case CreateApplication.call(params, actor) do
      {:ok, %{application: application}} ->
        :ok = Broadcaster.broadcast_application(application, "application.created")
        {:ok, application}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec get(Ecto.UUID.t()) :: Application.t() | nil
  def get(application_id), do: Repo.get(Application, application_id)

  @spec list(User.t(), map()) :: {:ok, [Application.t()]} | {:error, BravoCredit.Error.t()}
  def list(%User{} = user, params \\ %{}), do: Queries.list(user, params)

  @spec get_authorized(Ecto.UUID.t(), User.t()) ::
          {:ok, Application.t()} | {:error, BravoCredit.Error.t()}
  def get_authorized(application_id, %User{} = user) do
    case Queries.get(application_id) do
      nil ->
        {:error, BravoCredit.Errors.application_not_found(application_id)}

      %Application{} = application ->
        if application.country_code in user.country_access do
          {:ok, application}
        else
          {:error, BravoCredit.Errors.forbidden_country(application.country_code)}
        end
    end
  end

  @spec update_state(Ecto.UUID.t(), map(), User.t()) ::
          {:ok, Application.t()} | {:error, BravoCredit.Error.t()}
  def update_state(application_id, params, %User{} = user) do
    case UpdateApplicationState.call(application_id, params, user) do
      {:ok, %{application: application}} ->
        :ok = Broadcaster.broadcast_application(application, "application.state_changed")
        {:ok, application}

      {:error, error} ->
        {:error, error}
    end
  end
end
