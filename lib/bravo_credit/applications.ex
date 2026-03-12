defmodule BravoCredit.Applications do
  @moduledoc """
  Public application services for managing credit applications.
  """

  alias BravoCredit.Applications.Application
  alias BravoCredit.Pipelines.CreateApplication
  alias BravoCredit.Repo

  @spec create(map(), term()) ::
          {:ok, BravoCredit.Applications.Application.t()} | {:error, BravoCredit.Error.t()}
  def create(params, actor \\ "public_api") when is_map(params) do
    case CreateApplication.call(params, actor) do
      {:ok, %{application: application}} -> {:ok, application}
      {:error, error} -> {:error, error}
    end
  end

  @spec get(Ecto.UUID.t()) :: Application.t() | nil
  def get(application_id), do: Repo.get(Application, application_id)
end
