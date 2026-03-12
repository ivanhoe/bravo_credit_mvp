defmodule BravoCredit.Pipeline.Steps.ValidateParams do
  @moduledoc """
  Validates and normalizes the raw create application payload.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Applications.CreateInput
  alias BravoCredit.Errors

  @impl true
  def call(%{raw_params: raw_params} = context) do
    changeset = CreateInput.changeset(raw_params)

    if changeset.valid? do
      {:ok, %{context | input: Ecto.Changeset.apply_action!(changeset, :validate)}}
    else
      {:error, Errors.invalid_params(%{fields: errors_on(changeset)})}
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
