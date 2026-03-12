defmodule BravoCredit.Pipeline.Steps.MarkProviderProcessing do
  @moduledoc """
  Marks the application as being processed by the external provider.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Applications.Application
  alias BravoCredit.Errors
  alias BravoCredit.Repo

  @impl true
  def call(%{application: %Application{} = application} = context) do
    changeset =
      Application.update_changeset(application, %{
        status: :provider_processing
      })

    case Repo.update(changeset) do
      {:ok, updated_application} ->
        {:ok, %{context | application: updated_application}}

      {:error, changeset} ->
        {:error,
         Errors.internal_error("Failed to mark application as provider_processing", %{
           fields: errors_on(changeset)
         })}
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
