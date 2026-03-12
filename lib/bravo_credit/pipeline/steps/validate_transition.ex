defmodule BravoCredit.Pipeline.Steps.ValidateTransition do
  @moduledoc """
  Validates state transitions according to the application's state machine.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Applications.StatePolicy
  alias BravoCredit.Errors

  @impl true
  def call(%{application: application, raw_params: raw_params} = context) do
    with {:ok, target_state} <- parse_target_state(raw_params),
         :ok <-
           ensure_transition_allowed(application.country_code, application.status, target_state) do
      {:ok, %{context | decision: %{target_state: target_state}}}
    end
  end

  defp parse_target_state(raw_params) do
    raw_state = Map.get(raw_params, "state") || Map.get(raw_params, :state)

    if is_binary(raw_state) do
      try do
        normalized_state =
          raw_state
          |> String.trim()
          |> String.downcase()
          |> String.to_existing_atom()

        {:ok, normalized_state}
      rescue
        ArgumentError ->
          {:error, Errors.invalid_params(%{fields: %{state: ["is invalid"]}})}
      end
    else
      {:error, Errors.invalid_params(%{fields: %{state: ["must be present"]}})}
    end
  end

  defp ensure_transition_allowed(country_code, current_state, target_state) do
    if StatePolicy.allowed?(country_code, current_state, target_state) do
      :ok
    else
      {:error, Errors.invalid_transition(current_state, target_state)}
    end
  end
end
